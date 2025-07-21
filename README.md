# Hudu - Microsoft Fabric Connect Script

connect Hudu datapoints to Microsoft Fabric with ease and flexibility


# Designing your Tables / Schemas

You can dynamically set your My-Schema.ps1 (or other schema files if you'd like) to represent any section/subsection of data possible.

1. define what data you need in HuduFetchMap-
the Name is what the variable holding this data will be called and the Command is what gets executed to grab this data from Hudu.

2. Organize your schema / datatypes in DatasetSchemaJson. You can have multiple tables in a single schema if you'd like, but what's important is that you set both a name and a datatype. These will store your data once pushed

3. Set Tabulation Map