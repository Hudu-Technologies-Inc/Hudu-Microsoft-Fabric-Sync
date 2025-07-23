# Hudu - Microsoft Fabric Connect Script

connect Hudu datapoints to Microsoft Fabric with ease and flexibility

simply describe the data you want to commit in your schema json and rock-and-roll.

<img width="3050" height="1178" alt="example-startup" src="https://github.com/user-attachments/assets/9a59a519-7133-45c1-9c29-a48d61593908" />

## Overview

you can sync different schemas/datasets with different tables at different times if you even want to get that granular. A timestamp file for each schema that you sync will be placed in project folder for seeing sync-status at-a-glance. Each schemafile contains their own credential lookup info, so you can populate different schemafiles to different tenants if you so choose.

you can utilize custom functions to obtain, transform, calculate, anything you want, however you want. Each measured item is specifically defined by you! Whatever measurements you define is dynamically processed to a new MS Fabric Table

<img width="296" height="93" alt="image" src="https://github.com/user-attachments/assets/c97a7d49-a0c6-4b02-adb7-3b8bd9f7dc85" />

Just design what data you want to fetch, which filters you want to apply on that data, and what property of that data you want to measure in your fetch definitions. In your table definitions, just place your tables where you want them and assign which columns they should be given by name. The rest will be calculated and sent to Fabric.

## 1- Config and Setup

### Schema File Variables
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

### Entra/Azure App Registration Info

If you plan on running on schedule/unattended and/or in the background, it is reccomended to utilize Azure Keystore for secrets storage along with Client-Secret Authentication.
There are three possible routes for authenticating, depending on what has been filled out in your schemafile. The path of these three will be printed for you during script start.

- Missing Client Id or Tenant Id- Assumes that you dont have an app registration; starts up the registration helper for you and begin registration
- Client Id and Tenant Id are present, but no ClientSecret- Assumes you want to use device-code interactive authentication
- Client Id, Tenant Id, and ClientSecret Present- Assumes fully noninteractive syncing (only store client secret if using Azure Keystore or another secrets provider)

#### If you haven't already performed Azure/Entra Registration

If you haven't performed registration yet (and have permissions to do so), you can run the App Registration helper. To do this, simply set the clientid and tenantid variables to a blank string and it will begin registration when needed. The registration helper will require you log in with a user that is within the target Microsoft Tenant. Then, if you have adequate permissions in your org, it will automagically perform registration. After which, it will open 2 browser pages. If you want to run this script on schedule, noninteractively, elect to finish with the 'application permissions' directions printed in powershell. If you are just getting started, you can follow the 'delegated permissions' directions, which will allow you to authenticate with device authentication (interactive)

#### If you would perfer to manually performe Azure/Entra Registration

If you choose to do so, be sure to set these permissions (depending on whether you plan to access interactively or with a delegated user, or both)

**Delegated Permissions:** `Dataset.ReadWrite.All, Workspace.Read.All`
**Application Permissions:** `Tenant.Read.All, Dataset.ReadWrite.All, Workspace.ReadWrite.All`


## 2- Designing your Tables / Schemas

Make a copy of My-Schema.ps1 (or edit directly if you'd like)
The definitions for each columns comes down to a 'fetch definition' (how we get the data and what Fabric will expect) and the 'tables definitions' (the order of columns we want in Fabric)

You can construct as many tables as you'd like, each being either per-company or generalized across companies

### Fetch Definition

You can construct your 'fetch' list to contain all the data you want to fetch from Hudu, with any modifications, filters, etc. These can be done per-company or generally (with the same source data in fetch)

The default schemafile included with this project has some basic metrics and filter examples. The sky is the limit, however, and you can insert entire functions or even scripts into your filter definitions.

<img width="763" height="167" alt="image" src="https://github.com/user-attachments/assets/e30a4519-5206-4108-ad37-6cfbae38f0e2" />

Above, we have a simple Fetch Entry. You can see that we have our source data from Command, Datatype and Filter.
When constructing custom filters, all you have to remember is to return a PSCustomObject that contains a key named as your entry is named, and a value that you can calculate any way you want.

As long as you follow the pattern, you can calculate anything, anywhere, however you want. The scope of things you can calculate or measure is absolutely massive with just a little creativity!
<img width="787" height="275" alt="image" src="https://github.com/user-attachments/assets/eb85696f-7862-4bb0-976d-a7c33b1ddec9" />

In the end, making custom filters and metrics is super easy and can be done in a number of ways.

Really, anything from start to finish will be evaluated exactly like a tiny little script that takes data in, transforms/calculates it, and spits something else out

Fetch data can be used across tables in your dataset and are easy to construct. 
You can use the same upstream data, like in example to calculate or measure items across Hudu, or Per-Company. 
Per-Company tables will take the original upstream data and recalculate / re-evaluate it, but as it relates to every company in your Hudu instace.

<img width="384" height="298" alt="image" src="https://github.com/user-attachments/assets/b09862b9-a579-4460-8112-6fbcc359ee8a" />

Per-company calculations do require that the objects you're working with in 'Command' include a company Id, **but that's the only requirement.**

<img width="2386" height="876" alt="image" src="https://github.com/user-attachments/assets/0bba863e-1e68-497b-91b4-66d648ec5352" />

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

Tables that are not 'per-company' are calculated seperately


## Automating Hudu MSFabric Metrics with Task Scheduler

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
