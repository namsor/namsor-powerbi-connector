# About NamSor PowerBI Connector
Power BI Desktop is a free, stand-alone application from Microsoft. You can download it from the Microsoft Power BI web site at https://powerbi.microsoft.com/. It has rich, easy-to-use analytic capabilities and makes it painless to bring in data from a variety of sources.

Enrich your PowerBI Data with Gender and Origin/Ethnicity : any table that has personal names can be enriched.

Check you this video tutorial on producing a cool dashboard on the gender gap in the Film Industry, from IMDB 5000 dataset in data.world :

[![NamSor PowerBI Connector Tutorial on YouTube](http://img.youtube.com/vi/YZ__4MPqNkw/0.jpg)](http://www.youtube.com/watch?v=YZ__4MPqNkw "NamSor PowerBI Connector Tutorial on YouTube")

## Installing the Connector

1. Download and install the [Power BI Desktop](https://powerbi.microsoft.com/en-us/desktop/) application, if you haven't done so already.
2. Start Power BI Desktop and find the "Preview features" section in the program options. Under "Preview features", ensure that "Custom data connectors" is enabled.
3. Create a "[My Documents]\Microsoft Power BI Desktop\Custom Connectors" directory. Note: In the April 2018 version of Power BI Desktop or later, this directory is "[My Documents]\Power BI Desktop\Custom Connectors".
4. Download the NamSor Custom Connector file NamSorAPIConnector.mez and place it in this directory. If Power BI Desktop is running, you'll need to exit the program and restart it for this new connector to be found.
5. Download the NamSor Power BI template file [NamSor-PowerBI-Template.pbix](https://github.com/namsor/namsor-powerbi-connector/blob/master/NamSor-PowerBI-Template.pbix?raw=true) and open it in Power BI Desktop. This template includes sample NamSor reports and data relations. It relies on the Data Connector to load and refresh it's data.
6. You'll be prompted for a NamSor API Key upon startup. You can get a NamSor API Key from your NamSor Account page (https://api.namsor.com/).
7. Copy the NamSor API Key from your account page into Power BI Desktop and click save. Once you do that, Power BI Desktop will begin communicating with NamSor API to enrich your data model with Gender and Origin/Ethnicity data. 
8. If you run into a [PQ error : Please rebuild this data combination](https://github.com/namsor/namsor-powerbi-connector/issues/1), try Ignoring privacy level in File > Options and settings > Options and then Current File > Privacy.

## Appending Gender to your data tables
Names can be genderized either one-by-one, or by pages of a few hundred names. Read the [Wiki](https://github.com/namsor/namsor-powerbi-connector/wiki "Get Started") to get started.

This is a example of [data visualization](https://app.powerbi.com/view?r=eyJrIjoiMmZkZjhiNTYtMzZkYi00ODk3LWFmMjAtMzhhNjQzOGU3M2IyIiwidCI6ImYzN2YxMjc3LTJiZTEtNDdjZi1hNGJmLTQ0MjJiMWM4YTU0MiIsImMiOjl9 "Gender Gap among M&A professionals") after appending gender to an Excel file.

![GenderGap](https://github.com/namsor/namsor-powerbi-connector/blob/master/img/2017_GenderGap_in_MandA_v1.png)

## Appending Origin / Ethnicity to your data tables
NamSor Origin or Diaspora API work in similar way to the Gender API.

## Monitoring API Usage
The API usage can be monitored directly from PowerBI. There is an example dashboard in the provided template, NamSor-PowerBI-Template.pbix

## Additional Links and Resources
* [Data Connector Technical Reference](https://github.com/Microsoft/DataConnectors)
* [M Library Functions](https://msdn.microsoft.com/library/mt253322.aspx)
* [M Language Specification](https://msdn.microsoft.com/library/mt807488.aspx)
* [Power BI Developer Center](https://powerbi.microsoft.com/developers/)
* [Data Connector Tutorial](https://github.com/Microsoft/DataConnectors/tree/master/samples/TripPin)
