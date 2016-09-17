import Foundation
import WarpCore

class QBESearchStep: QBEStep {
	var query: String

	init(previous: QBEStep?, query: String) {
		self.query = query
		super.init(previous: previous)
	}

	required init(coder aDecoder: NSCoder) {
		self.query = aDecoder.decodeString(forKey: "query") ?? ""
		super.init(coder: aDecoder)
	}
	
	required init() {
		self.query = ""
		super.init()
	}

	override func encode(with coder: NSCoder) {
		coder.encodeString(self.query, forKey: "query")
		super.encode(with: coder)
	}

	override func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence {
		return QBESentence(format: "Search for [#]".localized,
			QBESentenceTextToken(value: self.query, callback: { [weak self] (newQuery) -> (Bool) in
				if let s = self {
					s.query = newQuery
				}
				return true
			})
		)
	}

	override func apply(_ data: Dataset, job: Job, callback: @escaping (Fallible<Dataset>) -> ()) {
		if self.query.isEmpty {
			callback(.success(data))
		}
		else {
			data.columns(job) { result in
				switch result {
				case .success(let cols):
					let exprs = cols.map { return Comparison(first: Literal(.string(self.query)), second: Sibling($0), type: .containsString) }
					let searchExpression = Call(arguments: exprs, type: .Or)
					callback(.success(data.filter(searchExpression)))

				case .failure(let e):
					return callback(.failure(e))
				}
			}
		}
	}
}
