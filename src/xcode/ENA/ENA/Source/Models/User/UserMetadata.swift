//
// 🦠 Corona-Warn-App
//

import Foundation

struct UserMetadata: Codable {
	var federalState: String
	// reference districtID
	var administrativeUnit: Int
	var ageGroup: AgeGroup

	enum CodingKeys: String, CodingKey {
		case federalState
		case administrativeUnit
		case ageGroup
	}

	init(
		federalState: String,
		administrativeUnit: Int,
		ageGroup: AgeGroup
	) {
		self.federalState = federalState
		self.administrativeUnit = administrativeUnit
		self.ageGroup = ageGroup
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		federalState = try container.decode(String.self, forKey: .federalState)
		administrativeUnit = try container.decode(Int.self, forKey: .administrativeUnit)
		ageGroup = try container.decode(AgeGroup.self, forKey: .ageGroup)
	}
}
