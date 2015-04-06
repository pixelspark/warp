import Foundation

class QBEFactory {
	typealias QBEStepViewCreator = (step: QBEStep?, delegate: QBESuggestionsViewDelegate) -> NSViewController?
	typealias QBEFileWriterCreator = (data: QBEData, locale: QBELocale, title: String) -> QBEFileWriter?
	
	static let sharedInstance = QBEFactory()
	
	private let fileWriters: [String: QBEFileWriterCreator] = [
		"html": {(data,locale,title) in QBEHTMLWriter(data: data, locale: locale, title: title)},
		"csv": {(data,locale,title) in QBECSVWriter(data: data, locale: locale)},
		"tsv": {(data,locale,title) in QBECSVWriter(data: data, locale: locale)}
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
		QBEMySQLSourceStep.className(): {QBEMySQLSourceStepView(step: $0, delegate: $1)}
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
		QBEMySQLSourceStep.className(): "MySQLIcon"
	]
	
	var fileTypesForWriting: [String] { get {
		return [String](fileWriters.keys)
	} }
	
	func fileWriterForType(type: String, data: QBEData, locale: QBELocale, title: String) -> QBEFileWriter? {
		if type == "html" {
			return QBEHTMLWriter(data: data, locale: locale, title: title)
		}
		return QBECSVWriter(data: data, locale: locale)
		
		/** FIXME: the code below generates invalid code in Swift 6.3b4...
		if let creator = fileWriters[type] {
			return creator(data: data, locale: locale, title: title)
		}
		return nil **/
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