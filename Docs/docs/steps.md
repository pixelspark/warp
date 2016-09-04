Warp can perform various transformation on data sets. Each transformation is contained in a *step*. You can create chains of steps that perform transformations sequentially. The data sets themselves are never modified by Warp - instead, Warp computes the transformations in-memory and only shows the end result. This allows you to change the chain of transformations easily.

You can add data transformations in various ways:

* Right-click a column, row or cell in a data table and select one of the transformations
* Use the 'Table', 'Rows' and 'Columns' menus in the menu bar to select a transformation
* Use one of the shortcut keys (see the menu bar!)

After adding, you can remove a transformation step by right-clicking it and selecting 'Remove step'. You can also drag steps around to re-order them.

Warp supports the following data analysis/transformation steps:

| Icon | Name | Description |
|------|------|-------------|
| ![Add/remove columns](../img/steps/columns.png) | [Add/remove columns](#add-remove-columns) | Removes or re-orders columns |
| ![Calculate column](../img/steps/calculate.png) | [Calculate column](#calculate-column) | Uses a formula to (re)create a column |
| ![Crawl](../img/steps/crawl.png) | [Crawl data](#crawl-data) | Fetches data from a web page for each row |
| ![Filter rows](../img/steps/filter.png) | [Filter rows](#filter-rows) | Filters rows based on a criterion |
| ![Flatten](../img/steps/flatten.png) | [Flatten data](#flatten-data) | Creates a row for each cell |
| ![Join](../img/steps/join.png) | [Join data](#join-data) | Links together data from two rows based on a criterion |
| ![Limit](../img/steps/limit.png) | [Limit the number of rows](#limit-the-number-of-rows) | Passes through or discards a fixed amount of rows |
| ![Merge data](../img/steps/merge.png) | [Merge data](#merge-data) | Appends one data set to the other |
| ![Pivot](../img/steps/pivot.png) | [Pivot data](#pivot-data) | Aggregates values while grouping rows into a table |
| ![Random](../img/steps/random.png) | [Randomly select rows](#randomly-select-rows) | Randomly selects rows (without replacement) |
| ![Remove duplicate rows](../img/steps/distinct.png) | [Remove duplicate rows](#remote-duplicate-rows) | Removes duplicate rows |
| ![Rename columns](../img/steps/rename.png) | [Rename columns](#rename-columns) | Renames columns |
| ![Sort rows](../img/steps/sort.png) | [Sort rows](#sort-rows) | Sorts rows by the values in selected columns |
| ![Transpose data](../img/steps/transpose.png) | [Transpose data](#transpose-data) | Swaps rows with columns |

# Add/remove columns

![Columns](../img/steps/columns.png)

Removes and/or re-orders columns according to settings.

If, for some reason, a column listed in the selection is not present in the data set, it is ignored.

# Calculate column

![Calculate](../img/steps/calculate.png)

Sets the value in a column by calculating a formula for each row. The formula may reference other values in the row. The following formula will calculate the uppercase version of the value in column 'last name':

````
UPPER([@last name])
````

If the target column does not exist yet, it is created. If the column already exists, the existing value is replaced. The formula may in that case reference the old value in the column with the special '@' identifier.

Read more about [writing formulas](formulas).

# Crawl data

![Crawl](../img/steps/crawl.png)

For each row, the crawl step will fetch a web page and place the result in a column. The URL to fetch is determined using a formula that is calculated for each row. 

Clicking the 'settings' button in the top right of the Warp window reveals the parameters that can be configured for a crawl step. For each row, the crawl step will fetch the document from the set URL and put the result data in (possibly new) columns:

* Column to place the result in: when provided, a new column with the given name will be added to the output data set, and it will contain the response obtained from the URL. If the content could not be obtained for a row, the column will contain an empty value.
* Column to place error message in: If an error occurs while fetching the URL for a row, this column will contain the error message returned by the system. 
* Column to place HTTP status code in: This column will contain the HTTP status code returned by the server when fetching the URL for the row.
* Column to place response time in: this column will contain the time it took for the crawl step to fetch the URL for this row, in seconds.

You may also configure the number of simultaneous requests that the crawl step is allowed to perform, as well as the maximum number of requests per seconds (both limits will be observed when they are both set).

# Filter rows

![Filter](../img/steps/filter.png)

Select rows based on a formula. The formula is calculated for each row, and if the formula returns a value that is logically 'true', the row will be included in the selection. For example, the following formula will only select rows that have a value greater than '27' in the 'age' column:

````
[@age]>27
````

[More about formulas](formulas.md)

# Flatten data

![Flatten](../img/steps/flatten.png)

The flatten step will create a row for each *cell* in the data set. The row will contain at least one column containing the value in the cell. It can be configured to also add two other columns:

* A column containing the name of the column in which the cell originally was
* A column containing the result of a [formula](formulas.md) calculated for the original row

The flatten step can be used to converted pivoted data back to unpivoted data, or to create 'key-value' pairs from a multidimensional data set. The number of rows returned by the flatten step is equal to the number of columns multiplied by the number of rows in the original data set.

# Join data

![Join](../img/steps/join.png)

# Limit the number of rows

![Limit](../img/steps/limit.png)

The limit step limits the number of rows from the source data set. It passes through the first N rows, and discards the rows following. 

Alternatively, it can be configured to discard *first* N rows, and pass through the rest.

# Merge data

![Merge](../img/steps/merge.png)

The merge step inserts the second data set after the first one. The resulting data set will contain the combined set of columns from either data set. When one data set does not contain a column from the other, the rows from that data set will contain an empty value for those columns.

# Pivot data

![Pivot](../img/steps/pivot.png)

The pivot step can be used to group and aggregate values. Its interface works much like the PivotTable functionality in Microsoft Excel.

![Pivot configuration](../img/pivot.png)

# Randomly select rows

![Random](../img/steps/random.png)

The random step randomly selects a specified number of rows from the source data. It does so without replacement (that is, any row can only be selected once). The chances of a row being selected are equal between rows.

Warp implements this step using so-called 'reservoir sampling'.

# Rename columns

![Rename](../img/steps/rename.png)

This step renames columns in a data set. The rename step will not allow renaming operations that result in the creation of two or more columns with the same name. The rename step can rename more than one column at the same time, all of which are processed at the same time. In particular, if you have columns A, B and C, you can rename A to B, B to C and C to A all at the same time. 

# Remove duplicate rows

![Distinct](../img/steps/distinct.png)

Removes duplicate rows from a data set. A row is duplicate if it is exactly equal to another row, i.e. if all values in the row are equal to the corresponding values in another row. Read more on when values are considered to be equal [here](semantics.md).

# Sort rows

![Sort](../img/steps/sort.png)

Sorts rows by their values in specified columns.

# Transpose data

![Transpose](../img/steps/transpose.png)

The transpose step swaps rows with columns.

In order to be able to transpose a data set, Warp must have the full data set in memory. Transposing can therefore be a time-consuming operation for larger data sets.