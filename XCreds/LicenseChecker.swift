//
//  LicenseChecker.swift
//  XCreds
//
//  Created by Timothy Perfitt on 3/28/23.
//

import Cocoa

class LicenseChecker: NSObject {
    enum LicenseState {
        case valid(Int)
        case invalid
        case trial(Int)
        case trialExpired
        case expired

    }

    func currentLicenseState() -> LicenseState {
        return .valid(0)
    }

}
