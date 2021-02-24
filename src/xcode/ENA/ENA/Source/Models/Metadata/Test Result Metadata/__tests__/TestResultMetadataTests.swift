////
// 🦠 Corona-Warn-App
//

@testable import ENA
import XCTest

class TestResultMetadataTests: XCTestCase {

	func testRegisteringNewTestMetadata_HighRisk() {
		let secureStore = MockTestStore()
		let riskCalculationResult = mockRiskCalculationResult()
		let date = Date()
		secureStore.dateOfConversionToHighRisk = Calendar.current.date(byAdding: .day, value: -1, to: date)
		secureStore.riskCalculationResult = riskCalculationResult

		Analytics.log(.testResultMetadata(.registerNewTestMetadata(date, "")))

		XCTAssertNotNil(secureStore.testResultMetadata, "The testResultMetadata should be initialized")
		XCTAssertEqual(secureStore.testResultMetadata?.testRegistrationDate, date, "incorrect RegistrationDate")
		XCTAssertEqual(secureStore.testResultMetadata?.riskLevelAtTestRegistration, riskCalculationResult.riskLevel, "incorrect risk level")
		XCTAssertEqual(
			secureStore.testResultMetadata?.daysSinceMostRecentDateAtRiskLevelAtTestRegistration,
			riskCalculationResult.numberOfDaysWithCurrentRiskLevel,
			"incorrect days since recent riskLEvel"
		)

		// the difference from dateOfConversionToHighRisk should be one day so 24 hours
		XCTAssertEqual(secureStore.testResultMetadata?.hoursSinceHighRiskWarningAtTestRegistration, 24, "incorrect hours")
	}

	func testRegisteringNewTestMetadata_LowRisk() {
		let secureStore = MockTestStore()
		let riskCalculationResult = mockRiskCalculationResult(risk: .low)
		let date = Date()
		secureStore.riskCalculationResult = riskCalculationResult

		Analytics.log(.testResultMetadata(.registerNewTestMetadata(date, "")))

		XCTAssertNotNil(secureStore.testResultMetadata, "The testResultMetadata should be initialized")
		XCTAssertEqual(secureStore.testResultMetadata?.testRegistrationDate, date, "incorrect RegistrationDate")
		XCTAssertEqual(secureStore.testResultMetadata?.riskLevelAtTestRegistration, riskCalculationResult.riskLevel, "incorrect risk level")
		XCTAssertEqual(
			secureStore.testResultMetadata?.daysSinceMostRecentDateAtRiskLevelAtTestRegistration,
			riskCalculationResult.numberOfDaysWithCurrentRiskLevel,
			"incorrect days since recent riskLEvel"
		)

		// the for low risk the value should always be -1
		XCTAssertEqual(secureStore.testResultMetadata?.hoursSinceHighRiskWarningAtTestRegistration, -1, "incorrect hours")
	}

	func testUpdatingTestResult_ValidResult_NotPreviousTestResultStored() {
		let secureStore = MockTestStore()
		let riskCalculationResult = mockRiskCalculationResult(risk: .low)
		secureStore.riskCalculationResult = riskCalculationResult

		if let registrationDate = Calendar.current.date(byAdding: .day, value: -4, to: Date()) {
			Analytics.log(.testResultMetadata(.registerNewTestMetadata(registrationDate, "")))
		} else {
			XCTFail("registration date is nil")
		}

		Analytics.log(.testResultMetadata(.updateTestResult(.positive, "")))
		XCTAssertEqual(secureStore.testResultMetadata?.testResult, TestResult.positive, "incorrect testResult")
		XCTAssertEqual(secureStore.testResultMetadata?.hoursSinceTestRegistration, (24 * 4), "incorrect hoursSinceTestRegistration")
	}

	func testUpdatingTestResult_ValidResult_previouslyStoredWithSameValue() {
		let secureStore = MockTestStore()
		let riskCalculationResult = mockRiskCalculationResult(risk: .low)
		secureStore.riskCalculationResult = riskCalculationResult
		Analytics.log(.testResultMetadata(.updateTestResult(.positive, "")))

		if let registrationDate = Calendar.current.date(byAdding: .day, value: -4, to: Date()) {
			Analytics.log(.testResultMetadata(.registerNewTestMetadata(registrationDate, "")))
		} else {
			XCTFail("registration date is nil")
		}

		Analytics.log(.testResultMetadata(.updateTestResult(.positive, "")))
		XCTAssertEqual(secureStore.testResultMetadata?.testResult, TestResult.positive, "incorrect testResult")

		// The date shouldn't be updated if the test result is the same as the old one
		XCTAssertEqual(secureStore.testResultMetadata?.hoursSinceTestRegistration, (24 * 4), "incorrect hoursSinceTestRegistration")
	}

	func testUpdatingTestResult_ValidResult_previouslyStoredWithDifferentValue() {
		let secureStore = MockTestStore()
		let riskCalculationResult = mockRiskCalculationResult(risk: .low)
		secureStore.riskCalculationResult = riskCalculationResult
		Analytics.log(.testResultMetadata(.updateTestResult(.pending, "")))

		if let registrationDate = Calendar.current.date(byAdding: .day, value: -4, to: Date()) {
			Analytics.log(.testResultMetadata(.registerNewTestMetadata(registrationDate, "")))
		} else {
			XCTFail("registration date is nil")
		}

		Analytics.log(.testResultMetadata(.updateTestResult(.positive, "")))
		XCTAssertEqual(secureStore.testResultMetadata?.testResult, TestResult.positive, "incorrect testResult")

		// The the date is updated if the risk results changes e.g from pendong to positive
		XCTAssertEqual(secureStore.testResultMetadata?.hoursSinceTestRegistration, (24 * 4), "incorrect hoursSinceTestRegistration")
	}

	func testUpdatingTestResult_Invalid() {
		let secureStore = MockTestStore()
		let riskCalculationResult = mockRiskCalculationResult(risk: .low)
		secureStore.riskCalculationResult = riskCalculationResult
		Analytics.log(.testResultMetadata(.updateTestResult(.pending, "")))

		if let registrationDate = Calendar.current.date(byAdding: .day, value: -4, to: Date()) {
			Analytics.log(.testResultMetadata(.registerNewTestMetadata(registrationDate, "")))
		} else {
			XCTFail("registration date is nil")
		}

		Analytics.log(.testResultMetadata(.updateTestResult(.invalid, "")))

		// The if the value is invalid  testResult shouldn't be updated
		XCTAssertNil(secureStore.testResultMetadata?.testResult, "incorrect testResult")

		// The if the value is invalid  hoursSinceTestRegistration shouldnt be updated and should remain the default value: 0
		XCTAssertEqual(secureStore.testResultMetadata?.hoursSinceTestRegistration, 0, "incorrect hoursSinceTestRegistration")
	}

	func testUpdatingTestResult_WithDifferentRegistrationToken_MetadataIsNotUpdated() {
		let secureStore = MockTestStore()
		let riskCalculationResult = mockRiskCalculationResult(risk: .low)
		secureStore.riskCalculationResult = riskCalculationResult

		if let registrationDate = Calendar.current.date(byAdding: .day, value: -4, to: Date()) {
			Analytics.log(.testResultMetadata(.registerNewTestMetadata(registrationDate, "Token")))
			Analytics.log(.testResultMetadata(.updateTestResult(.pending, "Token")))
		} else {
			XCTFail("registration date is nil")
		}

		// trying to update a test with a different token shouldn't work
		Analytics.log(.testResultMetadata(.updateTestResult(.positive, "Different Token")))
		// The if the value is valid but the token is different then the testResult shouldn't be updated
		XCTAssertEqual(secureStore.testResultMetadata?.testResult, .pending, "testResult shouldn't be updated")

		// trying to update a test with the correct token should work
		Analytics.log(.testResultMetadata(.updateTestResult(.positive, "Token")))
		// The if the value is valid and the token the same then the testResult should be updated
		XCTAssertEqual(secureStore.testResultMetadata?.testResult, .positive, "testResult should be updated")
	}

	private func mockRiskCalculationResult(risk: RiskLevel = .high) -> RiskCalculationResult {
		RiskCalculationResult(
			riskLevel: risk,
			minimumDistinctEncountersWithLowRisk: 0,
			minimumDistinctEncountersWithHighRisk: 0,
			mostRecentDateWithLowRisk: Date(),
			mostRecentDateWithHighRisk: Date(),
			numberOfDaysWithLowRisk: 0,
			numberOfDaysWithHighRisk: 2,
			calculationDate: Date(),
			riskLevelPerDate: [:],
			minimumDistinctEncountersWithHighRiskPerDate: [:]
		)
	}
}