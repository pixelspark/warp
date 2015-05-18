import Foundation

class QBEFactory {
	typealias QBEStepViewCreator = (step: QBEStep?, delegate: QBESuggestionsViewDelegate) -> NSViewController?
	typealias QBEFileWriterCreator = (locale: QBELocale, title: String?) -> (QBEFileWriter?)
	typealias QBEFileReaderCreator = (url: NSURL) -> QBEStep?
	
	static let sharedInstance = QBEFactory()
	
	private let fileWriters: [String: QBEFileWriter.Type] = [
		"html": QBEHTMLWriter.self,
		"csv": QBECSVWriter.self,
		"tsv": QBECSVWriter.self
	]
	
	private let fileReaders: [String: QBEFileReaderCreator] = [
		"public.comma-separated-values-text": {(url) in return QBECSVSourceStep(url: url)},
		"org.sqlite.v3": {(url) in return QBESQLiteSourceStep(url: url)}
	]
	
	private let stepViews: Dictionary<String, QBEStepViewCreator> = [
		QBESQLiteSourceStep.className(): {QBESQLiteSourceStepView(step: $0, delegate: $1)},
		QBELimitStep.className(): {QBELimitStepView(step: $0, delegate: $1)},
		QBEOffsetStep.className(): {QBEOffsetStepView(step: $0, delegate: $1)},
		QBERandomStep.className(): {QBERandomStepView(step: $0, delegate: $1)},
		QBECalculateStep.className(): {QBECalculateStepView(step: $0, delegate: $1)},
		QBEPivotStep.className(): {QBEPivotStepView(step: $0, delegate: $1)},
		QBECSVSourceStep.className(): {QBECSVStepView(step: $0, delegate: $1)},
		QBEFilterStep.className(): {QBEFilterStepView(step: $0, delegate: $1)},
		QBEFlattenStep.className(): {QBEFlattenStepView(step: $0, delegate: $1)},
		QBEPrestoSourceStep.className(): {QBEPrestoSourceStepView(step: $0, delegate: $1)},
		QBEColumnsStep.className(): {QBEColumnsStepView(step: $0, delegate: $1)},
		QBESortStep.className(): {QBESortStepView(step: $0, delegate: $1)},
		QBEMySQLSourceStep.className(): {QBEMySQLSourceStepView(step: $0, delegate: $1)},
		QBEJoinStep.className(): {QBEJoinStepView(step: $0, delegate: $1)},
		QBEPostgresSourceStep.className(): {QBEPostgresStepView(step: $0, delegate: $1)}
	]
	
	private let stepIcons = [
		QBETransposeStep.className(): "TransposeIcon",
		QBEPivotStep.className(): "PivotIcon",
		QBERandomStep.className(): "RandomIcon",
		QBEFilterStep.className(): "FilterIcon",
		QBELimitStep.className(): "LimitIcon",
		QBEOffsetStep.className(): "LimitIcon",
		QBECSVSourceStep.className(): "CSVIcon",
		QBESQLiteSourceStep.className(): "SQLIcon",
		QBECalculateStep.className(): "CalculateIcon",
		QBEColumnsStep.className(): "ColumnsIcon",
		QBESortColumnsStep.className(): "ColumnsIcon",
		QBEFlattenStep.className(): "FlattenIcon",
		QBEDistinctStep.className(): "DistinctIcon",
		QBEPrestoSourceStep.className(): "PrestoIcon",
		QBERasterStep.className(): "RasterIcon",
		QBESortStep.className(): "SortIcon",
		QBEMySQLSourceStep.className(): "MySQLIcon",
		QBEPostgresSourceStep.className(): "PostgresIcon",
		QBEJoinStep.className(): "JoinIcon"
	]
	
	var fileExtensionsForWriting: [String] { get {
		return [String](fileWriters.keys)
	} }
	
	var fileTypesForReading: [String] { get {
		return [String](fileReaders.keys)
	} }
	
	func stepForReadingFile(atURL: NSURL) -> QBEStep? {
		var error: NSError?
		if let type = NSWorkspace.sharedWorkspace().typeOfFile(atURL.path!, error: &error) {
			if let creator = fileReaders[type] {
				return creator(url: atURL)
			}
		}
		return nil
	}
	
	func fileWriterForType(type: String, locale: QBELocale, title: String) -> QBEFileWriter? {
		if let c = fileWriters[type] {
			return c(locale: locale, title: title)
		}
		return nil
	}
	
	func viewForStep(step: QBEStep, delegate: QBESuggestionsViewDelegate) -> NSViewController? {
		if let creator = stepViews[step.self.className] {
			return creator(step: step, delegate: delegate)
		}
		return nil
	}
	
	func iconForStep(step: QBEStep) -> String? {
		return stepIcons[step.className]
	}
	
	func iconForStepType(type: QBEStep.Type) -> String? {
		return stepIcons[type.className()]
	}
}