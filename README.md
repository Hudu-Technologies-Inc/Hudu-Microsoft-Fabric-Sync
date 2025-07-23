# Hudu - Microsoft Fabric Connect Script

connect Hudu datapoints to Microsoft Fabric with ease and flexibility

simply describe the data you want to commit in your schema json and rock-and-roll.

<img width="3050" height="1178" alt="example-startup" src="https://github.com/user-attachments/assets/9a59a519-7133-45c1-9c29-a48d61593908" />

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

## Automating Hudu MSFabric Metrics with Task Scheduler

If you want regular reports with your chosen filters/metrics/tables, you'll want to set up your secrets and names for secrets in Azure Key Store. After doing this, a pretty nifty way of accomplishing this deed is via Task Scheduler, which can be used to trigger metrics to sync whenever you'd like.

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
