# Hudu → Microsoft Fabric Connect Script

[original community post, July 2025](https://community.hudu.com/script-library-awpwerdu/post/integrate-hudu-data-into-microsoft-fabric-Nzwstjv8mBpx1Qp)

Connect Hudu datapoints to Microsoft Fabric with **ease and flexibility**.

> 1. **Setup and design** your schema  
> 2. **Complete** Entra app registration  
> 3. **Run and observe** your metrics come to life

The rest is **history** — **rich**, **actionable**, **informative** history.

<img width="3050" height="1178" alt="example-startup" src="https://github.com/user-attachments/assets/9a59a519-7133-45c1-9c29-a48d61593908" />

---

## Table of Contents

- [Overview](#overview)
- [1. Config and Setup](#1-config-and-setup)
  - [1-A. Schema File Variables](#1-a-schema-file-variables)
  - [1-B. Schema Setup](#1-b-schema-setup)
    - [Fetch Definition](#fetch-definition)
    - [Table Definition(s)](#table-definitions)
- [2. Entra / Azure App Registration](#2-entra--azure-app-registration)
- [3. Running and Invocation](#3-running-and-invocation)
  - [3A Automating with Task Scheduler](#3a-automating-with-task-scheduler)


---

## 1. Config and Setup

The only file you'll need to edit is your schema definition file. You can edit My-Schema.ps1 included in this repo or you can make a copy of it to reference the original later.

### 1-A. Schema File Variables

In your schemafile, you can configure any/all of the below items-
(registration info) ****if either of these is set to blank or null, the powerBI registration script will help get you started****
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

### 1-B. Schema Setup

You can construct as many tables as you'd like, each being either per-company or generalized across companies.

Make a copy of My-Schema.ps1 (or edit directly)

The definitions for each columns comes down to a 'fetch definition' (how we get the data and what Fabric will expect) and the 'tables definitions' (the order of columns we want in Fabric).

You can utilize custom functions to obtain, transform, calculate, anything you want, however you want. Each measured item is specifically defined by you and completely customizable. Whatever measurements you define is dynamically processed to a new MS Fabric Table.

<img width="296" height="93" alt="image" src="https://github.com/user-attachments/assets/c97a7d49-a0c6-4b02-adb7-3b8bd9f7dc85" />

**There are two parts to schema setup -**
1- Fetch Definitions - this is the upstream data that you'll use and how you'd like to measure/filter it.
2- Table Definitions - organize the fields you designed in your 'Fetch' section into different tables. Define if you want to measaure certain tables per-company.

> Fetch definitions can be reused between tables. Suppose you make a fetch definition to count all articles; you could then place that fetch definition in one table that counts them per-company and one that counts them across companies--since it's the same source data. 

You can sync  schemas/datasets with different tables at different times if you even want to get that granular. A timestamp file for each schema that you sync will be placed in a project folder for seeing sync-status at-a-glance. Each schemafile contains their own credential lookup info, so you can populate different schemafiles to different tenants if you choose to do so.

#### Fetch Definition


You can construct your 'fetch' list to contain all the data you want to fetch from Hudu, with any modifications, filters, etc. These can be done per-company or generally (with the same source data in fetch).

The default schemafile included with this project has some basic metrics and filter examples. The sky is the limit, however, and you can insert entire functions or even scripts into your filter definitions.

<img width="763" height="167" alt="image" src="https://github.com/user-attachments/assets/e30a4519-5206-4108-ad37-6cfbae38f0e2" />

Above, we have a simple Fetch Entry. You can see that we have our source data from Command, Datatype and Filter.
When constructing custom filters, all you have to remember is to return a PSCustomObject that contains a key named as your entry is named, and a value that you can calculate any way you want.

As long as you follow the pattern, you can calculate anything, anywhere, however you want. The scope of things you can calculate or measure is absolutely massive with just a little creativity!
<img width="787" height="275" alt="image" src="https://github.com/user-attachments/assets/eb85696f-7862-4bb0-976d-a7c33b1ddec9" />

Per-company calculations do require that the objects you're working with in 'Command' include a company Id, **but that's the only requirement** for secondary per-company filtering.

Fetch Entries require:

##### Name
This is the name you will reference from your table or between tables if reused

##### Command
This is the HuduAPI powershell module command needed to get the initial, prefiltered data. (See [HuduAPI PS Module](https://github.com/Hudu-Technologies-Inc/HuduAPI) for more infromation) 
For example, if you want to measure a subset of 'companies' you'd use {Get-HuduCompanies}.

##### Datatype
This is the datatype that your schema will use in Fabric. These are accepted datatypes in Fabric
common datatypes for Fabric- Int64, Double, Boolean, DateTime, String

##### Filter
This is how you want to filter your base data, describes the subest of command you seek to measure.
A filter has a (param), which represents the data you get from 'command'. With this, you can count, sort, average, or perform any arithmatic, string, date, or boolean functions you want. Just make sure that the datatype field matches the output of your filter. Your filter can be as long as you want, it's just a way of getting from A (command data) to B (your subset).


#### Table Definition(s)

Here, you define your tables and columns to be in an expected order for your dataset/schema.

<img width="384" height="298" alt="image" src="https://github.com/user-attachments/assets/b09862b9-a579-4460-8112-6fbcc359ee8a" />

Tables that are 'per-company' are calculated per-company and submitted 1-row-per-company.
Per-Company measurements have two additional columns (company id and company name) injected into them, so you can omit those from your definitions--they are automatic

<img width="2386" height="876" alt="image" src="https://github.com/user-attachments/assets/0bba863e-1e68-497b-91b4-66d648ec5352" />

Fetch data can be used across tables and can use the same upstream data. For Example, if your fetch data represents the count of articles, if you place that fetch column in a per-company table and a general table, the general table will measure ALL articles with that filter condition, the per-company will measure THAT COMPANY's Articles that match your filter condition.

---

## 2. Entra / Azure App Registration

If you plan on running on schedule/unattended and/or in the background, it is reccomended to utilize Azure Keystore for secrets storage along with Client-Secret Authentication.
There are three possible routes for authenticating, depending on what has been filled out in your schemafile. The path of these three will be printed for you during script start.

- Missing Client Id or Tenant Id- Assumes that you dont have an app registration; starts up the registration helper for you and begin registration
- Client Id and Tenant Id are present, but no ClientSecret- Assumes you want to use device-code interactive authentication
- Client Id, Tenant Id, and ClientSecret Present- Assumes fully noninteractive syncing (only store client secret if using Azure Keystore or another secrets provider)

### Using the Registration Helper

If you haven't performed registration yet (and have permissions to do so), you can run the App Registration helper. To do this, simply set the clientid and tenantid variables to a blank string and it will begin registration when the time is right. The registration helper will require you log in with a user that is within the target Microsoft Tenant. Then, if you have adequate permissions in your org, it will automagically perform registration. After which, it will open 2 browser pages. If you want to run this script on schedule, noninteractively, elect to finish with the 'application permissions' directions printed in powershell. If you are just getting started, you can follow the 'delegated permissions' directions, which will allow you to authenticate with device authentication (interactive)

### Manual App Registration

If you choose to do so, be sure to set these permissions (depending on whether you plan to access interactively or with a delegated user, or both)

**Delegated Permissions:** `Dataset.ReadWrite.All, Workspace.Read.All`
**Application Permissions:** `Tenant.Read.All, Dataset.ReadWrite.All, Workspace.ReadWrite.All`

---

## 3. Running and Invocation

### Manual Invocation

Once you have your Schema file(s) set up and ready, you can invoke a sync with 

```
. .\Sync-Fabric.ps1  -schemaFile .\your-schemafile
```
Further, if you supply `-DryRun $true` as an argument, no data will be pushed to Fabric yet- which can be helpful during design phase. Instead, your would-be tables and rows are printed for your review.

### 3A Automating with Task Scheduler

**If you want regular reports with your chosen filters/metrics/tables**, you'll want to set up your secrets and names for secrets in Azure Key Store. After doing this, a pretty nifty way of accomplishing this deed is via Task Scheduler, which can be used to trigger metrics to sync whenever you'd like.

<img width="275" height="300" alt="ts-example1" src="https://github.com/user-attachments/assets/ca4e8102-4905-424f-a86b-b5f7ccbfc607" />

If you set up Task scheduler for this, be sure that you set it up to run from an Azure/Entra/Domain-joined machine as a user in your forest.

<img width="500" height="400" alt="image" src="https://github.com/user-attachments/assets/24f0137e-afe7-4653-b7a5-5da55a970781" />

When setting things up for the first time it's important that you get a few things right, **namely your action/invocation**.

<img width="300" height="300" alt="ts-example2" src="https://github.com/user-attachments/assets/093b4def-d0eb-428d-9ba3-18d8be338599" />

for 'Program/Script' field, you'll want to make sure you browse-to or **point-to your powershell 7.5+ executable**.
`C:\Program Files\PowerShell\7\pwsh.exe`

For the 'Arguments' field, you can provide your args like beklow
`-ExecutionPolicy Bypass -File "C:\Users\Administrator\Documents\GitHub\fabulous-sync\Sync-Fabric.ps1" -schemaFile "C:\Users\Administrator\Documents\GitHub\fabulous-sync\masoni-schema.ps1"`

Lastly, for your 'Start-In' field, or working dir, you can **set that to the directory you cloned this project to**.
`C:\Users\Administrator\Documents\GitHub\yourclonedir`

<img width="1630" height="814" alt="invocation-args" src="https://github.com/user-attachments/assets/2fb84a4c-f0b0-4af5-b68c-8e3b58ed193f" />




