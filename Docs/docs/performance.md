Warp performs several optimization steps to increase the performance and responsiveness of calculations. The optimization steps are performed in the following stages:

* Step fusion
* Data operation coalescing and reordering
* Expression optimization
* SQL pushdown

## Step fusion

If two consecutive steps transform data in such a way that they cancel each other out, they are removed from the processing chain. For example, two consecutive transpositions result in the original data set. Note that Warp will notify you when you add a step that cancels out the last step. 

Steps are also fused if they can be logically combined. For instance, if the last step in a chain is sorting by a column, and you add a step that sorts by another column, both steps are combined into a single step that uses multi-level sorting.

## Data operation coalescing and reordering

On a lower level, data operations are 'coalesced' as well. Unlike step fusion, coalescing is not made visible to the end-user. For instance, if you have two consecutive filter steps, Warp will combine both into a single filter operation, using an AND expression. 

Warp may also reorder operations to improve performance. For instance, if you calculate a new column and then filter rows, Warp may decide to filter first, and then calculate the column, as long as the filter does not depend on the newly calculated value. In general Warp will try to order filter operations as early as possible, so the database can maximally use any indexes that may be present for a table.

## Expression optimization

Warp performs the following optimizations on expressions used in calculate and filer steps:

* Constant expressions are replaced with their static outcomes. 
* Warp checks if a comparison is made between expressions that are equivalent (e.g. [@column]=[@column] is always true). These are replaced with constants.

If a filter expression is constant 'false' or constant 'true', the filter can be removed completely.

## SQL pushdown

Warp translates data operations to SQL queries whenever possible for steps that operate on data from an SQL data source. This increases performance greatly, as it does not require transferring the full data set to Warp, and lets the database do the work. The database can make use of its caches and indexes to perform the work more efficiently as well.

Not all operations can be performed in SQL. Avoid the following operations to maintain maximum performance:

* Transposition
* Pivoting of data (aggregation by rows only is fine)

In some cases, Warp will upload data temporarily to a database to make it possible to perform a query in SQL. For instance, if a large table is joined with a small look-up table created in Warp, Warp can upload the look-up table as a temporary table in the database, and then perform the join fully in SQL.