# Hudu - Microsoft Fabric Connect Script

connect Hudu datapoints to Microsoft Fabric with ease and flexibility

simply describe the data you want to commit in your schema json and rock-and-roll.

## Overview

you can sync different schemas/datasets with different tables at different times if you even want to get that granular. A timestamp file for each schema that you sync will be placed in project folder for seeing sync-status at-a-glance. Each schemafile contains their own credential lookup info, so you can populate different schemafiles to different tenants if you so choose.

<img width="296" height="93" alt="image" src="https://github.com/user-attachments/assets/c97a7d49-a0c6-4b02-adb7-3b8bd9f7dc85" />

Just design what data you want to fetch, which filters you want to apply on that data, and what property of that data you want to measure in your fetch definitions. In your table definitions, just place your tables where you want them and assign which columns they should be given by name. The rest will be calculated and sent to Fabric.

## 1- Config and Setup

The only file you'll need to edit is your schema definition file. you can edit My-Schema.ps1 in-place or you can make a copy of it to reference the original later.

In your schemafile, you can configure any/all of the below items-
(registration info) ****if either of these is set to blank or null, powerBI registration script will help get you started****
- $clientId (PowerBI App Registration ID) 
- $tenantId (Microsoft Tenant Id)

(Az Keystore info) ****reccomended****
- $UseAzureKeyStore (whether or not to use AZ keystore for obtaining secrets)
- $AzVault_Name (your keyvault name)
- $HuduApiKeySecretName (secret name for hudu api key)
- $clientIdSecretName (secret name for powerBI app registration Client ID
- $clientSecretName (secret name for powerBI registration App Secret, if running noninteractively)
- $tenantIdSecretName (secret name for microsoft tenant id) [otherwise just set a variable to $tenantId if you dont need this as a secret]

(Hudu info)
- $HuduBaseUrl "yoururl.huducloud.com"

also a good place for static data that you want to compare/filter against, like dates
$age_threshold = (Get-Date).AddMonths(-6)

---

Once you have your Schema file(s) set up and ready, you can invoke a sync with 

. .\Sync-Fabric.ps1  -schemaFile .\your-schemafile


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

