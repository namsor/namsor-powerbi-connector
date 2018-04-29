# About NamSor PowerBI Connector
Power BI Desktop is a free, stand-alone application from Microsoft. You can download it from the Microsoft Power BI web site at https://powerbi.microsoft.com/. It has rich, easy-to-use analytic capabilities and makes it painless to bring in data from a variety of sources.

Enrich your PowerBI Data with Gender and Origin/Ethnicity : any table that has personal names can be enriched.

## Installing the Connector

1. Download and install the Power BI Desktop application, if you haven't done so already.
2. Start Power BI Desktop and find the "Preview features" section in the program options. Under "Preview features", ensure that "Custom data connectors" is enabled.
3. Create a "[My Documents]\Microsoft Power BI Desktop\Custom Connectors" directory. Note: In the April 2018 version of Power BI Desktop or later, this directory is "[My Documents]\Power BI Desktop\Custom Connectors"
4. Download the NamSor Custom Connector file NamSorAPIConnector.mez and place it in this directory. If Power BI Desktop is running, you'll need to exit the program and restart it for this new connector to be found.
5. Download the NamSor Power BI template file NamSor-PowerBI-Template.pbix and open it in Power BI Desktop. This template includes sample NamSor reports and data relations. It relies on the Data Connector to load and refresh it's data.
6. You'll be prompted for a NamSor API Key upon startup. You can get a NamSor API Key from your NamSor Account page (https://api.namsor.com/)
7. Copy the NamSor API Key from your account page into Power BI Desktop and click save. Once you do that, Power BI Desktop will begin communicating with NamSor API to enrich your data model with Gender and Origin/Ethnicity data. You can view it by clicking on the "NamSor" report.
There's a current limitation with custom data connectors. You cannot "Publish" this report to the Power BI web app. To view your data in the Power BI web app, please install NamSor from AppSource (this is a pending functionality).

## Making a Gender Gap report
Names can be genderized either one-by-one, or by pages of a few hundred names. Read the Wiki to get started.
https://github.com/namsor/namsor-powerbi-connector/wiki

This is a example of data visualization produced using the Gender Batch API Connector.

https://app.powerbi.com/view?r=eyJrIjoiMmZkZjhiNTYtMzZkYi00ODk3LWFmMjAtMzhhNjQzOGU3M2IyIiwidCI6ImYzN2YxMjc3LTJiZTEtNDdjZi1hNGJmLTQ0MjJiMWM4YTU0MiIsImMiOjl9

## Making a Diversity of Origin report
NamSor Origin or Diaspora API work in similar way to the Gender API, but produce likely country of origin, ethnicity based on personal names. 

## Monitoring API Usage
The API usage can be monitored directly from PowerBI. There is an example dashboard in the provided template.

## Additional Links and Resources
* [Data Connector Technical Reference](https://github.com/Microsoft/DataConnectors)
* [M Library Functions](https://msdn.microsoft.com/library/mt253322.aspx)
* [M Language Specification](https://msdn.microsoft.com/library/mt807488.aspx)
* [Power BI Developer Center](https://powerbi.microsoft.com/developers/)
* [Data Connector Tutorial](https://github.com/Microsoft/DataConnectors/tree/master/samples/TripPin)
