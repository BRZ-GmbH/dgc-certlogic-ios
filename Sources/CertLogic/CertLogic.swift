//
//  CertLogicEngine.swift
//
//
//  Created by Alexandr Chernyy on 08.06.2021.
//
import jsonlogic
import SwiftyJSON
import Foundation

public typealias Codable = Decodable & Encodable

public enum ValidationType {
  case all
  case issuer
  case destination
  case traveller
}

final public class CertLogicEngine {
  
  private var schema: JSON?
  private var payloadJSON: JSON?
  private var rules: [Rule]
  
  public init(schema: String, rules: [Rule]) {
    self.schema = JSON(parseJSON: schema)
    self.rules = rules
  }

  public init(schema: String, rulesData: Data) {
    self.schema = JSON(parseJSON: schema)
    self.rules = CertLogicEngine.getItems(from: rulesData)
  }

  public init(schema: String, rulesJSONString: String) {
    self.schema = JSON(parseJSON: schema)
    self.rules = CertLogicEngine.getItems(from: rulesJSONString)
  }

  public func updateRules(rules: [Rule]) {
    self.rules = rules
  }
  
  public func validate(filter: FilterParameter, external: ExternalParameter, payload: String, validationType: ValidationType = .all) -> [ValidationResult] {
    self.payloadJSON = JSON(parseJSON: payload)
    var result: [ValidationResult] = []

    var rulesItems = [Rule]()
    switch validationType {
    case .all:
      rulesItems = getListOfRulesForAll(filter: filter, issuerCountryCode: external.issuerCountryCode)
    case .issuer:
      rulesItems = getListOfRulesForIssuer(filter: filter, issuerCountryCode: external.issuerCountryCode)
    case .destination:
      rulesItems = getListOfRulesForDestination(filter: filter, issuerCountryCode: external.issuerCountryCode)
    case .traveller:
      rulesItems = getListOfRulesForTraveller(filter: filter, issuerCountryCode: external.issuerCountryCode)
    }
    if(rules.count == 0) {
      result.append(ValidationResult(rule: nil, result: .passed, validationErrors: nil))
      return result
    }
    guard let qrCodeSchemeVersion = self.payloadJSON?["ver"].rawValue as? String else {
      result.append(ValidationResult(rule: nil, result: .fail, validationErrors: nil))
      return result
    }
    rulesItems.forEach { rule in
        if !checkSchemeVersion(for: rule, qrCodeSchemeVersion: qrCodeSchemeVersion) || !checkEngineVersion(for: rule) || rule.engine != Constants.engine {
        result.append(ValidationResult(rule: rule, result: .open, validationErrors: [CertLogicError.openState]))
      } else {
        do {
          let jsonlogic = try JsonLogic(rule.logic.description)
          let results: Any = try jsonlogic.applyRule(to: getJSONStringForValidation(external: external, payload: payload))
          if results is Bool {
            if results as! Bool {
              result.append(ValidationResult(rule: rule, result: .passed, validationErrors: nil))
            } else {
              result.append(ValidationResult(rule: rule, result: .fail, validationErrors: nil))
            }
          } else {
            result.append(ValidationResult(rule: rule, result: .open, validationErrors: [CertLogicError.openState]))
          }
        } catch {
          result.append(ValidationResult(rule: rule, result: .open, validationErrors: [error]))
        }
      }
    }
      return result
  }
  
  // MARK: check scheme version from qr code and from rule
  private func checkSchemeVersion(for rule: Rule, qrCodeSchemeVersion: String) -> Bool {
    //Check if major version more 1 skip this rule
    guard abs(self.getVersion(from: qrCodeSchemeVersion) - self.getVersion(from: rule.schemaVersion)) < Constants.majorVersionForSkip else {
      return false
    }
    //Check if QR code version great or equal of rule code, if no skiped this rule
    // Scheme version of QR code always should be greate of equal of rule scheme version
    guard self.getVersion(from: qrCodeSchemeVersion) >= self.getVersion(from: rule.schemaVersion) else {
      return false
    }
    return true
  }
    
    // MARK: check scheme version from qr code and from rule
  private func checkEngineVersion(for rule: Rule) -> Bool {
      //Check if major version more 1 skip this rule
    guard abs(self.getVersion(from: rule.engineVersion) - self.getVersion(from: Constants.engineVersion)) < Constants.majorVersionForSkip else {
        return false
      }
      //Check if QR code version great or equal of rule code, if no skiped this rule
      // Scheme version of QR code always should be greate of equal of rule scheme version
    guard self.getVersion(from: rule.engineVersion) <= self.getVersion(from: Constants.engineVersion) else {
        return false
      }
      return true
  }
  
  // MARK: calculate scheme version in Int "1.0.0" -> 10000, "1.2.0" -> 10200, 2.0.1 -> 20001
  private func getVersion(from schemeString: String) -> Int {
    let codeVersionItems = schemeString.components(separatedBy: ".")
    var version: Int = 0
    let maxIndex = codeVersionItems.count - 1
    for index in 0...maxIndex {
      let division = Int(pow(Double(100), Double(Constants.maxVersion - index)))
      let calcVersion: Int = Int(codeVersionItems[index]) ?? 1
      let forSum: Int =  calcVersion * division
      version = version + forSum
    }
    return version
  }
  
  // MARK:
  private func getJSONStringForValidation(external: ExternalParameter, payload: String) -> String {
    guard let jsonData = try? defaultEncoder.encode(external) else { return ""}
    let externalJsonString = String(data: jsonData, encoding: .utf8)!
    
    var result = ""
    result = "{" + "\"\(Constants.external)\":" + "\(externalJsonString)" + "," + "\"\(Constants.payload)\":" + "\(payload)"  + "}"
    return result
  }
  
  // Get List of Rules for Country by Code
  private func getListOfRulesForAll(filter: FilterParameter, issuerCountryCode: String) -> [Rule] {
    var returnedRulesItems: [Rule] = []
    var generalRulesWithAcceptence = rules.filter { rule in
      return rule.countryCode.lowercased() == filter.countryCode.lowercased() && rule.ruleType == .acceptence && rule.certificateFullType == .general && filter.validationClock >= rule.validFromDate && filter.validationClock <= rule.validToDate
    }
    if let region = filter.region {
      generalRulesWithAcceptence = generalRulesWithAcceptence.filter { rule in
        rule.region?.lowercased() == region.lowercased()
      }
    } else {
      generalRulesWithAcceptence = generalRulesWithAcceptence.filter { rule in
        rule.region == nil
      }
    }
    
    var generalRulesWithInvalidation = rules.filter { rule in
      return rule.countryCode.lowercased() == issuerCountryCode.lowercased() && rule.ruleType == .invalidation && rule.certificateFullType == .general && filter.validationClock >= rule.validFromDate && filter.validationClock <= rule.validToDate
    }
    
    if let region = filter.region {
      generalRulesWithInvalidation = generalRulesWithInvalidation.filter { rule in
        rule.region?.lowercased() == region.lowercased()
      }
    } else {
      generalRulesWithInvalidation = generalRulesWithInvalidation.filter { rule in
        rule.region == nil
      }
    }
    
    let groupedGeneralRulesWithInvalidation = generalRulesWithInvalidation.group(by: \.identifier)
    let groupedGeneralRulesWithAcceptence = generalRulesWithAcceptence.group(by: \.identifier)

    //General Rule with Acceptence type and max Version number grouped by Identifier
    groupedGeneralRulesWithInvalidation.keys.forEach { key in
      let rules = groupedGeneralRulesWithInvalidation[key]
      if let maxRules = rules?.max(by: { (ruleOne, ruleTwo) -> Bool in
         return ruleOne.versionInt < ruleTwo.versionInt
      }) {
       returnedRulesItems.append( maxRules)
      }
    }
    groupedGeneralRulesWithAcceptence.keys.forEach { key in
      let rules = groupedGeneralRulesWithAcceptence[key]
      if let maxRules = rules?.max(by: { (ruleOne, ruleTwo) -> Bool in
         return ruleOne.versionInt < ruleTwo.versionInt
      }) {
       returnedRulesItems.append( maxRules)
      }
    }

    var certTypeRulesWithAcceptence = rules.filter { rule in
      return rule.countryCode.lowercased() == filter.countryCode.lowercased() && rule.ruleType == .acceptence  && rule.certificateFullType == filter.certificationType && filter.validationClock >= rule.validFromDate && filter.validationClock <= rule.validToDate
    }
    if let region = filter.region {
      certTypeRulesWithAcceptence = certTypeRulesWithAcceptence.filter { rule in
        rule.region?.lowercased() == region.lowercased()
      }
    } else {
      certTypeRulesWithAcceptence = certTypeRulesWithAcceptence.filter { rule in
        rule.region == nil
      }
    }

    var certTypeRulesWithInvalidation = rules.filter { rule in
      return rule.countryCode.lowercased() == issuerCountryCode.lowercased() && rule.ruleType == .invalidation && rule.certificateFullType == filter.certificationType && filter.validationClock >= rule.validFromDate && filter.validationClock <= rule.validToDate
    }
    if let region = filter.region {
      certTypeRulesWithInvalidation = certTypeRulesWithInvalidation.filter { rule in
        rule.region?.lowercased() == region.lowercased()
      }
    } else {
      certTypeRulesWithInvalidation = certTypeRulesWithInvalidation.filter { rule in
        rule.region == nil
      }
    }

    let groupedCertTypeRulesWithAcceptence = certTypeRulesWithAcceptence.group(by: \.identifier)
    let groupedCertTypeRulesWithInvalidation = certTypeRulesWithInvalidation.group(by: \.identifier)

    groupedCertTypeRulesWithAcceptence.keys.forEach { key in
      let rules = groupedCertTypeRulesWithAcceptence[key]
      if let maxRules = rules?.max(by: { (ruleOne, ruleTwo) -> Bool in
         return ruleOne.versionInt < ruleTwo.versionInt
      }) {
       returnedRulesItems.append( maxRules)
      }
    }
    groupedCertTypeRulesWithInvalidation.keys.forEach { key in
      let rules = groupedCertTypeRulesWithInvalidation[key]
      if let maxRules = rules?.max(by: { (ruleOne, ruleTwo) -> Bool in
         return ruleOne.versionInt < ruleTwo.versionInt
      }) {
       returnedRulesItems.append( maxRules)
      }
    }

    return returnedRulesItems
  }

  // Get List of Rules for Country by Code
  private func getListOfRulesForIssuer(filter: FilterParameter, issuerCountryCode: String) -> [Rule] {
    var returnedRulesItems: [Rule] = []
    
    var generalRulesWithInvalidation = rules.filter { rule in
      return rule.countryCode.lowercased() == issuerCountryCode.lowercased() && rule.ruleType == .invalidation && rule.certificateFullType == .general && filter.validationClock >= rule.validFromDate && filter.validationClock <= rule.validToDate
    }
    
    if let region = filter.region {
      generalRulesWithInvalidation = generalRulesWithInvalidation.filter { rule in
        rule.region?.lowercased() == region.lowercased()
      }
    } else {
      generalRulesWithInvalidation = generalRulesWithInvalidation.filter { rule in
        rule.region == nil
      }
    }
    
    let groupedGeneralRulesWithInvalidation = generalRulesWithInvalidation.group(by: \.identifier)
 
    //General Rule with Acceptence type and max Version number grouped by Identifier
    groupedGeneralRulesWithInvalidation.keys.forEach { key in
      let rules = groupedGeneralRulesWithInvalidation[key]
      if let maxRules = rules?.max(by: { (ruleOne, ruleTwo) -> Bool in
         return ruleOne.versionInt < ruleTwo.versionInt
      }) {
       returnedRulesItems.append( maxRules)
      }
    }
 
    var certTypeRulesWithInvalidation = rules.filter { rule in
      return rule.countryCode.lowercased() == issuerCountryCode.lowercased() && rule.ruleType == .invalidation && rule.certificateFullType == filter.certificationType && filter.validationClock >= rule.validFromDate && filter.validationClock <= rule.validToDate
    }
    if let region = filter.region {
      certTypeRulesWithInvalidation = certTypeRulesWithInvalidation.filter { rule in
        rule.region?.lowercased() == region.lowercased()
      }
    } else {
      certTypeRulesWithInvalidation = certTypeRulesWithInvalidation.filter { rule in
        rule.region == nil
      }
    }

    let groupedCertTypeRulesWithInvalidation = certTypeRulesWithInvalidation.group(by: \.identifier)
    groupedCertTypeRulesWithInvalidation.keys.forEach { key in
      let rules = groupedCertTypeRulesWithInvalidation[key]
      if let maxRules = rules?.max(by: { (ruleOne, ruleTwo) -> Bool in
         return ruleOne.versionInt < ruleTwo.versionInt
      }) {
       returnedRulesItems.append( maxRules)
      }
    }

    return returnedRulesItems
  }

  // Get List of Rules for Country by Code
  private func getListOfRulesForDestination(filter: FilterParameter, issuerCountryCode: String) -> [Rule] {
    var returnedRulesItems: [Rule] = []

    var certTypeRulesWithAcceptence = rules.filter { rule in
      return rule.countryCode.lowercased() == filter.countryCode.lowercased() && rule.ruleType == .acceptence  && rule.certificateFullType == filter.certificationType && filter.validationClock >= rule.validFromDate && filter.validationClock <= rule.validToDate
    }
    if let region = filter.region {
      certTypeRulesWithAcceptence = certTypeRulesWithAcceptence.filter { rule in
        rule.region?.lowercased() == region.lowercased()
      }
    } else {
      certTypeRulesWithAcceptence = certTypeRulesWithAcceptence.filter { rule in
        rule.region == nil
      }
    }

    let groupedCertTypeRulesWithAcceptence = certTypeRulesWithAcceptence.group(by: \.identifier)

    groupedCertTypeRulesWithAcceptence.keys.forEach { key in
      let rules = groupedCertTypeRulesWithAcceptence[key]
      if let maxRules = rules?.max(by: { (ruleOne, ruleTwo) -> Bool in
         return ruleOne.versionInt < ruleTwo.versionInt
      }) {
       returnedRulesItems.append( maxRules)
      }
    }
    return returnedRulesItems
  }
  
  // Get List of Rules for Country by Code
  private func getListOfRulesForTraveller(filter: FilterParameter, issuerCountryCode: String) -> [Rule] {
    var returnedRulesItems: [Rule] = []
    var generalRulesWithAcceptence = rules.filter { rule in
      return rule.countryCode.lowercased() == filter.countryCode.lowercased() && rule.ruleType == .acceptence && rule.certificateFullType == .general && filter.validationClock >= rule.validFromDate && filter.validationClock <= rule.validToDate
    }
    if let region = filter.region {
      generalRulesWithAcceptence = generalRulesWithAcceptence.filter { rule in
        rule.region?.lowercased() == region.lowercased()
      }
    } else {
      generalRulesWithAcceptence = generalRulesWithAcceptence.filter { rule in
        rule.region == nil
      }
    }
    
    let groupedGeneralRulesWithAcceptence = generalRulesWithAcceptence.group(by: \.identifier)

    groupedGeneralRulesWithAcceptence.keys.forEach { key in
      let rules = groupedGeneralRulesWithAcceptence[key]
      if let maxRules = rules?.max(by: { (ruleOne, ruleTwo) -> Bool in
         return ruleOne.versionInt < ruleTwo.versionInt
      }) {
       returnedRulesItems.append( maxRules)
      }
    }


    return returnedRulesItems
  }


  static public func getItems<T:Decodable>(from jsonString: String) -> [T] {
    guard let jsonData = jsonString.data(using: .utf8) else { return []}
    return getItems(from: jsonData)
  }
  static public func getItems<T:Decodable>(from jsonData: Data) -> [T] {
    guard let items: [T] = try? defaultDecoder.decode([T].self, from: jsonData) else { return [] }
    return items
  }

  static public func getItem<T:Decodable>(from jsonString: String) -> T? {
    guard let jsonData = jsonString.data(using: .utf8) else { return nil}
    return getItem(from: jsonData)
  }
  static public func getItem<T:Decodable>(from jsonData: Data) -> T? {
    guard let item: T = try? defaultDecoder.decode(T.self, from: jsonData) else { return nil }
    return item
  }
  
  // Get details rule error by affected fields
  public func getDetailsOfError(rule: Rule, filter: FilterParameter) -> Dictionary<String, String> {
    var result: Dictionary<String, String> = Dictionary()
    rule.affectedString.forEach { key in
      var keyToGetValue: String? = nil
      let arrayKeys = key.components(separatedBy: ".")
      // For affected fields like "ma"
      if arrayKeys.count == 0 {
        keyToGetValue = key
      }
      // For affected fields like r.0.fr
      if arrayKeys.count == 3 {
        keyToGetValue = arrayKeys.last
      }
      // All other keys will skiped (example: "r.0")
      if let keyToGetValue = keyToGetValue {
        if let newValue = self.getValueFromSchemeBy(filter: filter, key: keyToGetValue), let newPayloadValue = self.getValueFromPayloadBy(filter: filter, key: keyToGetValue) {
          result[newValue] = newPayloadValue
        }
      }
    }
    return result
  }
  
  private func getValueFromSchemeBy(filter: FilterParameter, key: String) -> String? {
    var section = Constants.testEntry
    if filter.certificationType == .recovery {
      section = Constants.recoveryEntry
    }
    if filter.certificationType == .vaccination {
      section = Constants.vaccinationEntry
    }
    if filter.certificationType == .test {
      section = Constants.testEntry
    }
    if let newValue = schema?[Constants.schemeDefsSection][section][Constants.properties][key][Constants.description].string {
      return newValue
    }
    return nil
  }
  
  private func getValueFromPayloadBy(filter: FilterParameter, key: String) -> String? {
    var section = Constants.payloadTestEntry
    if filter.certificationType == .recovery {
      section = Constants.payloadRecoveryEntry
    }
    if filter.certificationType == .vaccination {
      section = Constants.payloadVaccinationEntry
    }
    if filter.certificationType == .test {
      section = Constants.payloadTestEntry
    }
    if let newValue = self.payloadJSON?[section][0][key].string {
      return newValue
    }
    if let newValue = self.payloadJSON?[section][0][key].number {
      return newValue.stringValue
    }
    return nil
  }
}

extension CertLogicEngine {
  private enum Constants {
    static let payload = "payload"
    static let external = "external"
    static let defSchemeVersion = "1.0.0"
    static let maxVersion: Int = 2
    static let majorVersionForSkip: Int = 10000
    static let engineVersion = "1.0.0"
    static let engine = "CERTLOGIC"

    static let testEntry = "test_entry"
    static let vaccinationEntry = "vaccination_entry"
    static let recoveryEntry = "recovery_entry"
    //Schema section
    static let schemeDefsSection = "$defs"
    static let properties = "properties"
    static let description = "description"
    //Payload section
    static let payloadTestEntry = "t"
    static let payloadVaccinationEntry = "v"
    static let payloadRecoveryEntry = "r"
  }
}
