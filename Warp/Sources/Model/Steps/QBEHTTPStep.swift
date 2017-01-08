/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import Alamofire
import WarpCore

class QBEHTTPStream: WarpCore.Stream {
	let columnNames = OrderedSet<Column>([Column("Data")])
	let url: String
	private let mutex = Mutex()
	private var first = true

	init(url: String) {
		self.url = url
	}

	func columns(_ job: Job, callback: @escaping (Fallible<OrderedSet<Column>>) -> ()) {
		callback(.success(self.columnNames))
	}

	func fetch(_ job: Job, consumer: @escaping Sink) {
		let first = self.mutex.locked { () -> Bool in
			if self.first {
				self.first = false
				return true
			}
			return false
		}

		if first {
			if let url = URL(string: self.url) {
				let request = NSMutableURLRequest(url: url)
				request.httpMethod = "GET"
				request.cachePolicy = .reloadRevalidatingCacheData

				Alamofire.request(request as URLRequest).responseString(encoding: String.Encoding.utf8) { response in
					let value: Value
					if let data = response.result.value {
						value = Value(data)
					}
					else {
						value = .invalid
					}

					let rows = [[value]]
					consumer(.success(rows), .finished)
				}
			}
			else {
				consumer(.failure("The URL to load data from is invalid.".localized), .finished)
			}
		}
		else {
			consumer(.success([]), .finished)
		}
	}

	func clone() -> WarpCore.Stream {
		return QBEHTTPStream(url: self.url)
	}
}

class QBEHTTPStep: QBEStep {
	var url: Expression

	required init(coder aDecoder: NSCoder) {
		self.url = aDecoder.decodeObject(of: Expression.self, forKey: "url") ?? Literal(Value("http://localhost"))
		super.init(coder: aDecoder)
	}

	required init() {
		self.url = Literal(Value("http://localhost"))
		super.init()
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: NSLocalizedString("Download data at [#]", comment: ""),
		   QBESentenceFormulaToken(expression: self.url, locale: locale, callback: { [weak self] (newExpression) -> () in
				self?.url = newExpression
			})
		)
	}

	override func encode(with coder: NSCoder) {
		coder.encode(self.url, forKey: "url")
		super.encode(with: coder)
	}

	override func fullDataset(_ job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		if let url = self.url.apply(Row(), foreign: nil, inputValue: nil).stringValue {
			callback(.success(StreamDataset(source: QBEHTTPStream(url: url))))
		}
		else {
			callback(.failure("URL must be a string".localized))
		}
	}

	override func exampleDataset(_ job: Job, maxInputRows: Int, maxOutputRows: Int, callback: @escaping  (Fallible<Dataset>) -> ()) {
		return self.fullDataset(job, callback: callback)
	}

	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		fatalError("Should never be called")
	}
}
