# Hudu - Microsoft Fabric Connect Script

connect Hudu datapoints to Microsoft Fabric with ease and flexibility

simply describe the data you want to commit in your schema json and rock-and-roll.

## 1- Config and Setup

The only file you'll need to edit is your schema definition file. you can edit My-Schema.ps1 in-place or you can make a copy of it to reference the original later.

### App Registration

If you plan on running on schedule/unattended and/or in the background, it is reccomended to utilize Azure Keystore for secrets storage along with Client-Secret Authentication.


## 2- Designing your Tables / Schemas

Make a copy of My-Schema.ps1 (or edit directly if you'd like)
The definitions for each columns comes down to a 'fetch definition' (how we get the data and what Fabric will expect) and the 'tables definitions' (the order of columns we want in Fabric)

You can construct as many tables as you'd like, each being either per-company or generalized across companies

### Fetch Definition

You can construct your 'fetch' list to contain all the data you want to fetch from Hudu, with any modifications, filters, etc. These can be done per-company or as a general table.

Fetch data can be used across tables in your dataset and are easy to construct. 
Entries require:

#### Name
This is the name you will reference from your table or between tables if reused

#### Command
This is the HuduAPI powershell module command needed to get the initial, prefiltered data
If you want to measure a subset of 'companies', for example, you'd use {Get-HuduCompanies}.

#### Datatype
This is the datatype that your schema will use in Fabric. These are accepted datatypes in Fabric
common datatypes for Fabric- Int64, Double, Boolean, DateTime, String

#### Filter
This is how you want to filter your base data, describes the subest of command you seek to measure.
A filter has a (param), which represents the data you get from 'command'. With this, you can count, sort, average, or perform any arithmatic, string, date, or boolean functions you want. Just make sure that the datatype field matches the output of your filter. Your filter can be as long as you want, it's just a way of getting from A (command data) to B (your subset)


### Table Definition(s)

Here, you define your table or tables' columns to be in an expected order.

Tables that are 'per-company' are calculated per-company and submitted 1-row-per-company
Per-Company measurements have an additional column (company id) injected into them, so no need to differentiate in your schema def

Tables that are not 'per-company' are calculated on their own.

## 3- Automating and running regular reporting intervals

