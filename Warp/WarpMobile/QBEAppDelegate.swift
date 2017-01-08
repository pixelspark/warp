/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import UIKit
import WarpCore

@UIApplicationMain
class QBEAppDelegate: UIResponder, UIApplicationDelegate {
	var window: UIWindow?

	var locale: Language {
		let language = UserDefaults.standard.string(forKey: "locale") ?? Language.defaultLanguage
		return Language(language: language)
	}

	class var sharedInstance: QBEAppDelegate { get {
		return UIApplication.shared.delegate as! QBEAppDelegate
	} }

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
		return true
	}

	func application(_ application: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey: Any]) -> Bool {
		/*
		`options[UIApplicationOpenURLOptionsOpenInPlaceKey]` will be set if
		the app doesn't need to make a copy of the document to open or edit it.
		For example, the document could be in the ubiquitous container of the
		application.
		*/
		guard let shouldOpenInPlace = options[UIApplicationOpenURLOptionsKey.openInPlace] as? Bool else {
			return false
		}

		guard let navigation = window?.rootViewController as? UINavigationController else {
			return false
		}

		guard let documentBrowserController = navigation.viewControllers.first as? QBEDocumentBrowserViewController else {
			return false
		}

		documentBrowserController.openDocumentAtURL(url, copyBeforeOpening: !shouldOpenInPlace)
		return true
	}
}
