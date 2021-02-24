////
// 🦠 Corona-Warn-App
//

import Foundation

typealias Analytics = PPAnalyticsCollector

/// Singleton to collect the analytics data and to save it in the database, to load it from the database, to remove every analytics data from the store. This also triggers a submission.
enum PPAnalyticsCollector {

	// MARK: - Internal

	/// Setup Analytics for regular use
	static func setup(
		store: Store,
		submitter: PPAnalyticsSubmitter
	) {
		guard let store = store as? (Store & PPAnalyticsData) else {
			Log.error("I will never submit any analytics data. Could not cast to correct store protocol", log: .ppa)
			fatalError("I will never submit any analytics data. Could not cast to correct store protocol")
		}
		PPAnalyticsCollector.store = store
		PPAnalyticsCollector.submitter = submitter
	}

	/// Setup Analytics for testing.
	static func setupMock(
		store: (Store & PPAnalyticsData)? = nil,
		submitter: PPAnalyticsSubmitter? = nil
	) {
		PPAnalyticsCollector.store = store
		PPAnalyticsCollector.submitter = submitter
	}

	static func log(_ dataType: PPADataType) {

		guard let consent = store?.isPrivacyPreservingAnalyticsConsentGiven,
			  consent == true else {
			Log.info("Forbidden to log any analytics data due to missing user consent", log: .ppa)
			return
		}

		Log.debug("Logging analytics data: \(dataType)", log: .ppa)
		switch dataType {
		case let .userData(userMetadata):
			Analytics.logUserMetadata(userMetadata)
		case let .riskExposureMetadata(riskExposureMetadata):
			Analytics.logRiskExposureMetadata(riskExposureMetadata)
		case let .clientMetadata(clientMetadata):
			Analytics.logClientMetadata(clientMetadata)
		case let .testResultMetadata(TestResultMetadata):
			Analytics.logTestResultMetadata(TestResultMetadata)
		case let .keySubmissionMetadata(keySubmissionMetadata):
			Analytics.logKeySubmissionMetadata(keySubmissionMetadata)
		case let .exposureWindowsMetadata(exposureWindowsMetadata):
			Analytics.logExposureWindowsMetadata(exposureWindowsMetadata)
		case let .submissionMetadata(submissionMetadata):
			Analytics.logSubmissionMetadata(submissionMetadata)
		}

		Analytics.triggerAnalyticsSubmission()
	}

	static func deleteAnalyticsData() {
		store?.currentRiskExposureMetadata = nil
		store?.previousRiskExposureMetadata = nil
		store?.userMetadata = nil
		store?.lastSubmittedPPAData = nil
		store?.lastAppReset = nil
		store?.lastSubmissionAnalytics = nil
		store?.clientMetadata = nil
		store?.testResultMetadata = nil
		store?.keySubmissionMetadata = nil
		store?.exposureWindowsMetadata = nil
		Log.info("Deleted all analytics data in the store", log: .ppa)
	}

	/// Triggers the submission of all collected analytics data. Only if all checks success, the submission is done. Otherwise, the submission is aborted. Optionally, you can specify a completion handler to get success or failures.
	static func triggerAnalyticsSubmission(completion: ((Result<Void, PPASError>) -> Void)? = nil) {
		guard let submitter = submitter else {
			Log.warning("I cannot submit analytics data. Perhaps i am a mock or setup was not called correctly?", log: .ppa)
			return
		}
		submitter.triggerSubmitData(completion: completion)
	}


	#if !RELEASE

	/// ONLY FOR TESTING. Returns the last submitted data.
	static func mostRecentAnalyticsData() -> String? {
		return store?.lastSubmittedPPAData
	}

	/// ONLY FOR TESTING. Return the constructed proto-file message to look into the data we would submit.
	static func getPPADataMessage() -> SAP_Internal_Ppdd_PPADataIOS? {
		guard let submitter = submitter else {
			Log.warning("I cannot get actual analytics data. Perhaps i am a mock or setup was not called correctly?")
			return nil
		}
		return submitter.getPPADataMessage()
	}

	/// ONLY FOR TESTING. Triggers for the dev menu a forced submission of the data, whithout any checks.
	static func forcedAnalyticsSubmission(completion: @escaping (Result<Void, PPASError>) -> Void) {
		guard let submitter = submitter else {
			Log.warning("I cannot trigger a forced submission. Perhaps i am a mock or setup was not called correctly?")
			return completion(.failure(.generalError))
		}
		return submitter.forcedSubmitData(completion: completion)
	}

	#endif

	// MARK: - Private

	private static var _store: (Store & PPAnalyticsData)?

	// wrapper property to add a log when the value is nil
	private static var store: (Store & PPAnalyticsData)? {
		get {
			if _store == nil {
				Log.error("I cannot log or read analytics data. Perhaps i am a mock or setup was not called correctly?", log: .ppa)
			}
			return _store
		}
		set {
			_store = newValue
		}
	}

	private static var submitter: PPAnalyticsSubmitter?

	// MARK: - UserMetada

	private static func logUserMetadata(_ userMetadata: PPAUserMetadata) {
		switch userMetadata {
		case let .complete(metaData):
			store?.userMetadata = metaData
		}
	}

	// MARK: - RiskExposureMetadata

	private static func logRiskExposureMetadata(_ riskExposureMetadata: PPARiskExposureMetadata) {
		switch riskExposureMetadata {
		case let .complete(metaData):
			store?.currentRiskExposureMetadata = metaData
		case let .updateRiskExposureMetadata(riskCalculationResult):
			Analytics.updateRiskExposureMetadata(riskCalculationResult)
		}
	}

	private static func updateRiskExposureMetadata(_ riskCalculationResult: RiskCalculationResult) {
		let riskLevel = riskCalculationResult.riskLevel
		let riskLevelChangedComparedToPreviousSubmission: Bool
		let dateChangedComparedToPreviousSubmission: Bool

		// if there is a risk level value stored for previous submission
		if store?.previousRiskExposureMetadata?.riskLevel != nil {
			if riskLevel !=
				store?.previousRiskExposureMetadata?.riskLevel {
				// if there is a change in risk level
				riskLevelChangedComparedToPreviousSubmission = true
			} else {
				// if there is no change in risk level
				riskLevelChangedComparedToPreviousSubmission = false
			}
		} else {
			// for the first time, the field is set to false
			riskLevelChangedComparedToPreviousSubmission = false
		}

		// if there is most recent date store for previous submission
		if store?.previousRiskExposureMetadata?.mostRecentDateAtRiskLevel != nil {
			if riskCalculationResult.mostRecentDateWithCurrentRiskLevel !=
				store?.previousRiskExposureMetadata?.mostRecentDateAtRiskLevel {
				// if there is a change in date
				dateChangedComparedToPreviousSubmission = true
			} else {
				// if there is no change in date
				dateChangedComparedToPreviousSubmission = false
			}
		} else {
			// for the first time, the field is set to false
			dateChangedComparedToPreviousSubmission = false
		}

		guard let mostRecentDateWithCurrentRiskLevel = riskCalculationResult.mostRecentDateWithCurrentRiskLevel else {
			// most recent date is not available because of no exposure
			let newRiskExposureMetadata = RiskExposureMetadata(
				riskLevel: riskLevel,
				riskLevelChangedComparedToPreviousSubmission: riskLevelChangedComparedToPreviousSubmission,
				dateChangedComparedToPreviousSubmission: dateChangedComparedToPreviousSubmission
			)
			Analytics.log(.riskExposureMetadata(.complete(newRiskExposureMetadata)))
			return
		}
		let newRiskExposureMetadata = RiskExposureMetadata(
			riskLevel: riskLevel,
			riskLevelChangedComparedToPreviousSubmission: riskLevelChangedComparedToPreviousSubmission,
			mostRecentDateAtRiskLevel: mostRecentDateWithCurrentRiskLevel,
			dateChangedComparedToPreviousSubmission: dateChangedComparedToPreviousSubmission
		)
		Analytics.log(.riskExposureMetadata(.complete(newRiskExposureMetadata)))
	}


	// MARK: - ClientMetadata

	private static func logClientMetadata(_ clientMetadata: PPAClientMetadata) {
		switch clientMetadata {
		case let .complete(metaData):
			store?.clientMetadata = metaData
		case .setClientMetaData:
			Analytics.setClientMetaData()
		}
	}

	private static func setClientMetaData() {
		let eTag = store?.appConfigMetadata?.lastAppConfigETag
		Analytics.log(.clientMetadata(.complete(ClientMetadata(etag: eTag))))
	}

	// MARK: - TestResultMetadata

	private static func logTestResultMetadata(_ TestResultMetadata: PPATestResultMetadata) {
		switch TestResultMetadata {
		case let .complete(metaData):
			store?.testResultMetadata = metaData
		case let .testResult(testResult):
			store?.testResultMetadata?.testResult = testResult
		case let .testResultHoursSinceTestRegistration(hoursSinceTestRegistration):
			store?.testResultMetadata?.hoursSinceTestRegistration = hoursSinceTestRegistration
		case let .updateTestResult(testResult, token):
			Analytics.updateTestResult(testResult, token)
		case let .registerNewTestMetadata(date, token):
			Analytics.registerNewTestMetadata(date, token)
		}
	}

	private static func updateTestResult(_ testResult: TestResult, _ token: String) {
		// we only save metadata for tests submitted on QR code,and there is the only place in the app where we set the registration date
		guard store?.testResultMetadata?.testRegistrationToken == token,
			  let registrationDate = store?.testResultMetadata?.testRegistrationDate else {
			Log.warning("Could not update test meta data result due to testRegistrationDate is nil", log: .ppa)
			return
		}

		let storedTestResult = store?.testResultMetadata?.testResult
		// if storedTestResult != newTestResult ---> update persisted testResult and the hoursSinceTestRegistration
		// if storedTestResult == nil ---> update persisted testResult and the hoursSinceTestRegistration
		// if storedTestResult == newTestResult ---> do nothing

		if storedTestResult == nil || storedTestResult != testResult {
			switch testResult {
			case .positive, .negative, .pending:
				Analytics.log(.testResultMetadata(.testResult(testResult)))

				switch store?.testResultMetadata?.testResult {
				case .positive, .negative, .pending:
					let diffComponents = Calendar.current.dateComponents([.hour], from: registrationDate, to: Date())
					Analytics.log(.testResultMetadata(.testResultHoursSinceTestRegistration(diffComponents.hour)))
				default:
					Analytics.log(.testResultMetadata(.testResultHoursSinceTestRegistration(nil)))
				}

			case .expired, .invalid:
				break
			}
		}
	}

	private static func registerNewTestMetadata(_ date: Date = Date(), _ token: String) {
		guard let riskCalculationResult = store?.riskCalculationResult else {
			Log.warning("Could not register new test meta data due to riskCalculationResult is nil", log: .ppa)
			return
		}
		var testResultMetadata = TestResultMetadata(registrationToken: token)
		testResultMetadata.testRegistrationDate = date
		testResultMetadata.riskLevelAtTestRegistration = riskCalculationResult.riskLevel
		testResultMetadata.daysSinceMostRecentDateAtRiskLevelAtTestRegistration = riskCalculationResult.numberOfDaysWithCurrentRiskLevel

		Analytics.log(.testResultMetadata(.complete(testResultMetadata)))

		switch riskCalculationResult.riskLevel {
		case .high:
			guard let timeOfRiskChangeToHigh = store?.dateOfConversionToHighRisk else {
				Log.warning("Could not log risk calculation result due to timeOfRiskChangeToHigh is nil", log: .ppa)
				return
			}
			let differenceInHours = Calendar.current.dateComponents([.hour], from: timeOfRiskChangeToHigh, to: date)
			store?.testResultMetadata?.hoursSinceHighRiskWarningAtTestRegistration = differenceInHours.hour
		case .low:
			store?.testResultMetadata?.hoursSinceHighRiskWarningAtTestRegistration = -1
		}


	}

	// MARK: - KeySubmissionMetadata

	// swiftlint:disable:next cyclomatic_complexity
	private static func logKeySubmissionMetadata(_ keySubmissionMetadata: PPAKeySubmissionMetadata) {
		switch keySubmissionMetadata {
		case let .complete(metadata):
			store?.keySubmissionMetadata = metadata
		case let .submitted(submitted):
			store?.keySubmissionMetadata?.submitted = submitted
		case let .submittedInBackground(inBackground):
			store?.keySubmissionMetadata?.submittedInBackground = inBackground
		case let .submittedAfterCancel(afterCancel):
			store?.keySubmissionMetadata?.submittedAfterCancel = afterCancel
		case let .submittedAfterSymptomFlow(afterSymptomFlow):
			store?.keySubmissionMetadata?.submittedAfterSymptomFlow = afterSymptomFlow
		case let .submittedWithTeletan(withTeletan):
			store?.keySubmissionMetadata?.submittedWithTeleTAN = withTeletan
		case let .lastSubmissionFlowScreen(flowScreen):
			store?.keySubmissionMetadata?.lastSubmissionFlowScreen = flowScreen
		case let .advancedConsentGiven(advanced):
			store?.keySubmissionMetadata?.advancedConsentGiven = advanced
		case let .hoursSinceTestResult(hours):
			store?.keySubmissionMetadata?.hoursSinceTestResult = hours
		case let .keySubmissionHoursSinceTestRegistration(hours):
			store?.keySubmissionMetadata?.hoursSinceTestRegistration = hours
		case let .daysSinceMostRecentDateAtRiskLevelAtTestRegistration(date):
			store?.keySubmissionMetadata?.daysSinceMostRecentDateAtRiskLevelAtTestRegistration = date
		case let .hoursSinceHighRiskWarningAtTestRegistration(hours):
			store?.keySubmissionMetadata?.hoursSinceHighRiskWarningAtTestRegistration = hours
		case .setHoursSinceTestResult:
			Analytics.setHoursSinceTestResult()
		case .setHoursSinceTestRegistration:
			Analytics.setHoursSinceTestRegistration()
		case .setHoursSinceHighRiskWarningAtTestRegistration:
			Analytics.setHoursSinceHighRiskWarningAtTestRegistration()
		case .setDaysSinceMostRecentDateAtRiskLevelAtTestRegistration:
			Analytics.setDaysSinceMostRecentDateAtRiskLevelAtTestRegistration()
		}
	}

	private static func setHoursSinceTestResult() {
		guard let resultDateTimeStamp = store?.testResultReceivedTimeStamp else {
			Log.warning("Could not log hoursSinceTestResult due to testResultReceivedTimeStamp is nil", log: .ppa)
			return
		}

		let timeInterval = TimeInterval(resultDateTimeStamp)
		let resultDate = Date(timeIntervalSince1970: timeInterval)
		let diffComponents = Calendar.current.dateComponents([.hour], from: resultDate, to: Date())
		store?.keySubmissionMetadata?.hoursSinceTestResult = Int32(diffComponents.hour ?? 0)
	}

	private static func setHoursSinceTestRegistration() {
		guard let registrationDate = store?.testRegistrationDate else {
			Log.warning("Could not log hoursSinceTestRegistration due to testRegistrationDate is nil", log: .ppa)
			return
		}

		let diffComponents = Calendar.current.dateComponents([.hour], from: registrationDate, to: Date())
		store?.keySubmissionMetadata?.hoursSinceTestRegistration = Int32(diffComponents.hour ?? 0)
	}

	private static func setDaysSinceMostRecentDateAtRiskLevelAtTestRegistration() {
		guard let numberOfDaysWithCurrentRiskLevel = store?.riskCalculationResult?.numberOfDaysWithCurrentRiskLevel  else {
			Log.warning("Could not log daysSinceMostRecentDateAtRiskLevelAtTestRegistration due to numberOfDaysWithCurrentRiskLevel is nil", log: .ppa)
			return
		}
		store?.keySubmissionMetadata?.daysSinceMostRecentDateAtRiskLevelAtTestRegistration = Int32(numberOfDaysWithCurrentRiskLevel)
	}

	private static func setHoursSinceHighRiskWarningAtTestRegistration() {
		guard let riskLevel = store?.riskCalculationResult?.riskLevel  else {
			Log.warning("Could not log hoursSinceHighRiskWarningAtTestRegistration due to riskLevel is nil", log: .ppa)
			return
		}
		switch riskLevel {
		case .high:
			guard let timeOfRiskChangeToHigh = store?.dateOfConversionToHighRisk,
				  let registrationTime = store?.testRegistrationDate else {
				Log.warning("Could not log risk calculation result due to timeOfRiskChangeToHigh is nil", log: .ppa)
				return
			}
			let differenceInHours = Calendar.current.dateComponents([.hour], from: timeOfRiskChangeToHigh, to: registrationTime)
			store?.keySubmissionMetadata?.hoursSinceHighRiskWarningAtTestRegistration = Int32(differenceInHours.hour ?? -1)
		case .low:
			store?.keySubmissionMetadata?.hoursSinceHighRiskWarningAtTestRegistration = -1
		}
	}

	// MARK: - ExposureWindowsMetadata

	private static func logExposureWindowsMetadata(_ exposureWindowsMetadata: PPAExposureWindowsMetadata) {
		switch exposureWindowsMetadata {
		case let .complete(metadata):
			store?.exposureWindowsMetadata = metadata
		case let .collectExposureWindows(riskCalculationProtocol):
			Analytics.collectExposureWindows(riskCalculationProtocol)
		}
	}

	private static func collectExposureWindows(_ riskCalculation: RiskCalculationProtocol) {
		self.clearReportedExposureWindowsQueueIfNeeded()

		let mappedSubmissionExposureWindows: [SubmissionExposureWindow] = riskCalculation.mappedExposureWindows.map {
			SubmissionExposureWindow(
				exposureWindow: $0.exposureWindow,
				transmissionRiskLevel: $0.transmissionRiskLevel,
				normalizedTime: $0.normalizedTime,
				hash: generateSHA256($0.exposureWindow),
				date: $0.date
			)
		}

		if let metadata = store?.exposureWindowsMetadata {
			// if store is initialized:
			// - Queue if new: if the hash of the Exposure Window not included in reportedExposureWindowsQueue, the Exposure Window is added to reportedExposureWindowsQueue.
			for exposureWindow in mappedSubmissionExposureWindows {
				if !metadata.reportedExposureWindowsQueue.contains(where: { $0.hash == exposureWindow.hash }) {
					store?.exposureWindowsMetadata?.newExposureWindowsQueue.append(exposureWindow)
					store?.exposureWindowsMetadata?.reportedExposureWindowsQueue.append(exposureWindow)
				}
			}
		} else {
			// if store is not initialized:
			// - Initialize and add all of the exposure windows to both "newExposureWindowsQueue" and "reportedExposureWindowsQueue" arrays
			store?.exposureWindowsMetadata = ExposureWindowsMetadata(
				newExposureWindowsQueue: mappedSubmissionExposureWindows,
				reportedExposureWindowsQueue: mappedSubmissionExposureWindows
			)
		}
	}

	private static func clearReportedExposureWindowsQueueIfNeeded() {
		if let nonExpiredWindows = store?.exposureWindowsMetadata?.reportedExposureWindowsQueue.filter({
			guard let day = Calendar.current.dateComponents([.day], from: $0.date, to: Date()).day else {
				Log.debug("Exposure Window is removed from reportedExposureWindowsQueue as the date component is nil", log: .ppa)
				return false
			}
			return day < 15
		}) {
			store?.exposureWindowsMetadata?.reportedExposureWindowsQueue = nonExpiredWindows
		}
	}

	private static func generateSHA256(_ window: ExposureWindow) -> String? {
		let encoder = JSONEncoder()
		do {
			let windowData = try encoder.encode(window)
			return windowData.sha256String()
		} catch {
			Log.error("ExposureWindow Encoding error", log: .ppa, error: error)
		}
		return nil
	}

	// MARK: - SubmissionMetadata

	private static func logSubmissionMetadata(_ submissionMetadata: PPASubmissionMetadata) {
		switch submissionMetadata {
		case let .lastAppReset(date):
			store?.lastAppReset = date
		}
	}
}

protocol PPAnalyticsData: AnyObject {
	/// Last succesfull submission of analytics data. Needed for analytics submission.
	var lastSubmissionAnalytics: Date? { get set }
	/// Date of last app reset. Needed for analytics submission.
	var lastAppReset: Date? { get set }
	/// Content of last submitted data. Needed for analytics submission dev menu.
	var lastSubmittedPPAData: String? { get set }
	/// Analytics data.
	var currentRiskExposureMetadata: RiskExposureMetadata? { get set }
	/// Analytics data.
	var previousRiskExposureMetadata: RiskExposureMetadata? { get set }
	/// Analytics data.
	var userMetadata: UserMetadata? { get set }
	/// Analytics data.
	var clientMetadata: ClientMetadata? { get set }
	/// Analytics data
	var keySubmissionMetadata: KeySubmissionMetadata? { get set }
	/// Analytics data.
	var testResultMetadata: TestResultMetadata? { get set }
	/// Analytics data.
	var exposureWindowsMetadata: ExposureWindowsMetadata? { get set }
}

extension SecureStore: PPAnalyticsData {

	var lastSubmissionAnalytics: Date? {
		get { kvStore["lastSubmissionAnalytics"] as Date? }
		set { kvStore["lastSubmissionAnalytics"] = newValue }
	}

	var lastAppReset: Date? {
		get { kvStore["lastAppReset"] as Date? }
		set { kvStore["lastAppReset"] = newValue }
	}

	var lastSubmittedPPAData: String? {
		get { kvStore["lastSubmittedPPAData"] as String? }
		set { kvStore["lastSubmittedPPAData"] = newValue }
	}

	var currentRiskExposureMetadata: RiskExposureMetadata? {
		get { kvStore["currentRiskExposureMetadata"] as RiskExposureMetadata? ?? nil }
		set { kvStore["currentRiskExposureMetadata"] = newValue }
	}

	var previousRiskExposureMetadata: RiskExposureMetadata? {
		get { kvStore["previousRiskExposureMetadata"] as RiskExposureMetadata? ?? nil }
		set { kvStore["previousRiskExposureMetadata"] = newValue }
	}

	var userMetadata: UserMetadata? {
		get { kvStore["userMetadata"] as UserMetadata? ?? nil }
		set { kvStore["userMetadata"] = newValue }
	}

	var testResultMetadata: TestResultMetadata? {
		get { kvStore["testResultaMetadata"] as TestResultMetadata? ?? nil }
		set { kvStore["testResultaMetadata"] = newValue }
	}

	var clientMetadata: ClientMetadata? {
		get { kvStore["clientMetadata"] as ClientMetadata? ?? nil }
		set { kvStore["clientMetadata"] = newValue }
	}

	var keySubmissionMetadata: KeySubmissionMetadata? {
		get { kvStore["keySubmissionMetadata"] as KeySubmissionMetadata? ?? nil }
		set { kvStore["keySubmissionMetadata"] = newValue }
	}

	var exposureWindowsMetadata: ExposureWindowsMetadata? {
		get { kvStore["exposureWindowsMetadata"] as ExposureWindowsMetadata? ?? nil }
		set { kvStore["exposureWindowsMetadata"] = newValue }
	}
}