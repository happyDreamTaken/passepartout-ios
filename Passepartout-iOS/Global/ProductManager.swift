//
//  ProductManager.swift
//  Passepartout-iOS
//
//  Created by Davide De Rosa on 4/6/19.
//  Copyright (c) 2019 Davide De Rosa. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of Passepartout.
//
//  Passepartout is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Passepartout is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Passepartout.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import StoreKit
import Convenience
import SwiftyBeaver
import Kvitto
import PassepartoutCore

private let log = SwiftyBeaver.self

class ProductManager: NSObject {
    private static let lastFullVersionNumber = "1.8.1"

    private static let lastFullVersionBuild = "2016"

    static let shared = ProductManager()
    
    private let inApp: InApp<Product>
    
    private var purchasedAppVersion: String?
    
    private var purchasedFeatures: Set<Product>
    
    private override init() {
        inApp = InApp()
        purchasedAppVersion = nil
        purchasedFeatures = []
        
        super.init()

        reloadReceipt()
    }
    
    func listProducts(completionHandler: (([SKProduct]) -> Void)?) {
        guard inApp.products.isEmpty else {
            completionHandler?(inApp.products)
            return
        }
        inApp.requestProducts(withIdentifiers: Product.all) { _ in
            completionHandler?(self.inApp.products)
        }
    }

    func purchase(_ product: SKProduct, completionHandler: @escaping (InAppPurchaseResult, Error?) -> Void) {
        inApp.purchase(product: product) {
            if $0 == .success {
                self.reloadReceipt()
            }
            completionHandler($0, $1)
        }
    }

    // MARK: In-app eligibility
    
    private func reloadReceipt() {
        guard let url = Bundle.main.appStoreReceiptURL else {
            log.warning("No App Store receipt found!")
            return
        }
        guard let receipt = Receipt(contentsOfURL: url) else {
            log.error("Could not parse App Store receipt!")
            return
        }

        purchasedAppVersion = receipt.originalAppVersion
        purchasedFeatures.removeAll()

        if let version = purchasedAppVersion {
            log.debug("Original purchased version: \(version)")

            // treat former purchases as full versions
            if version <= ProductManager.lastFullVersionNumber {
                purchasedFeatures.insert(.fullVersion)
            }
        }
        if let iapReceipts = receipt.inAppPurchaseReceipts {
            log.debug("In-app receipts:")
            iapReceipts.forEach {
                guard let pid = $0.productIdentifier, let date = $0.originalPurchaseDate else {
                    return
                }
                log.debug("\t\(pid) [\(date)]")
            }
            for r in iapReceipts {
                guard let pid = r.productIdentifier, let product = Product(rawValue: pid) else {
                    continue
                }
                purchasedFeatures.insert(product)
            }
        }
        log.info("Purchased features: \(purchasedFeatures)")
    }

    func isFullVersion() -> Bool {
        guard !AppConstants.Flags.isBeta else {
            return true
        }
        return purchasedFeatures.contains(.fullVersion)
    }
    
    func isEligible(forFeature feature: Product) -> Bool {
        guard !isFullVersion() else {
            return true
        }
        return purchasedFeatures.contains(feature)
    }

    func isEligible(forProvider name: Infrastructure.Name) -> Bool {
        guard !isFullVersion() else {
            return true
        }
        return purchasedFeatures.contains {
            return $0.rawValue.hasSuffix("providers.\(name.rawValue)")
        }
    }
}
