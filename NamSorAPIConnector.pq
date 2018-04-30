section NamSorAPIConnector;

client_secret = Text.FromBinary(Extension.Contents("client_secret"));
is_beta = true;
category = "Online Services";
learn_more_url = "https://github.com/namsor/namsor-powerbi-connector";
// batch size for API calls : 100 or 500 (must be strictly less than 1000)
batch_size = 500; 

[DataSource.Kind="NamSorAPIGenderBatchConnector", Publish="NamSorAPIGenderBatchConnector.Publish"]
shared NamSorAPIConnector.GenderBatch = Value.ReplaceType(GenderBatchImpl, GenderBatchAPIType);
[DataSource.Kind="NamSorAPIGenderConnector", Publish="NamSorAPIGenderConnector.Publish"]
shared NamSorAPIConnector.Gender = Value.ReplaceType(GenderImpl, GenderAPIType);
[DataSource.Kind="NamSorAPIOriginBatchConnector", Publish="NamSorAPIOriginBatchConnector.Publish"]
shared NamSorAPIConnector.OriginBatch = Value.ReplaceType(OriginBatchImpl, OriginBatchAPIType);
[DataSource.Kind="NamSorAPIOriginConnector", Publish="NamSorAPIOriginConnector.Publish"]
shared NamSorAPIConnector.Origin = Value.ReplaceType(OriginImpl, OriginAPIType);

[DataSource.Kind="NamSorAPIDiasporaBatchConnector", Publish="NamSorAPIDiasporaBatchConnector.Publish"]
shared NamSorAPIConnector.DiasporaBatch = Value.ReplaceType(DiasporaBatchImpl, DiasporaBatchAPIType);
[DataSource.Kind="NamSorAPIDiasporaConnector", Publish="NamSorAPIDiasporaConnector.Publish"]
shared NamSorAPIConnector.Diaspora = Value.ReplaceType(DiasporaImpl, DiasporaAPIType);

[DataSource.Kind="NamSorAPIUsageHistoryConnector", Publish="NamSorAPIUsageHistoryConnector.Publish"]
shared NamSorAPIConnector.UsageHistory = Value.ReplaceType(UsageHistoryImpl, UsageHistoryAPIType);
[DataSource.Kind="NamSorAPICurrentUsageConnector", Publish="NamSorAPICurrentUsageConnector.Publish"]
shared NamSorAPIConnector.CurrentUsage = Value.ReplaceType(CurrentUsageImpl, CurrentUsageAPIType);

GenderBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have firstName, lastName columns.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional firstNameColumn as (type text meta [
        Documentation.FieldCaption = "First Name Column",
        Documentation.FieldDescription = "The name of column containing : The First Name(s) incuding Middle Name(s)",
        Documentation.SampleValues = {"firstName"}
    ]),
    optional lastNameColumn as (type text meta [
        Documentation.FieldCaption = "Last Name Column",
        Documentation.FieldDescription = "The name of column containing : The Family Name / Surname / Last Name(s)",
        Documentation.SampleValues = {"lastName"}
    ])
    )
    as table meta [
        Documentation.Name = "Append Gender to Table",
        Documentation.LongDescription = "Infer Gender from Name(s) in a Table",
        Documentation.Examples = {[
            Description = "Infer likely gender from firstName, lastName",
            Code = "NamSorAPIConnector.GenderBatch(""John"",""Smith"")",
            Result = "male"
        ],[
            Description = "Infer likely gender from firstName, lastName and geographic context",
            Code = "NamSorAPIConnector.GenderBatch(""Elena"",""Rossini"",""it"")",
            Result = "female"
        ]}
    ];

// BUG/ANNOYANCE : when params are not optional - there keeps asking crendentials ... when they are, there is an error after cnnecting
GenderBatchImpl = (optional inputTable as table, optional firstNameColumn as text, optional lastNameColumn as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{firstNameColumn, type text}, {lastNameColumn, type text}}),
        #"Renamed Columns" = Table.RenameColumns(#"Changed Type",{{firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}}),
        #"Removed Other Columns" = Table.SelectColumns(#"Renamed Columns",{"firstName", "lastName"}),
        #"DistinctNames" = Table.Distinct(#"Removed Other Columns"),
        #"DistinctNamesNonNull" = Table.SelectRows(#"DistinctNames", each ([firstName] <> null) and ([lastName] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"DistinctNamesNonNull", "id", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([id]/batch_size)),

        // https://social.technet.microsoft.com/Forums/en-US/0f9fec02-4469-4c56-92ec-00d46b26b3fc/how-to-automateparameterizeloop-power-query?forum=powerquery
        Batch.Results = (batchid) => let 
                    #"Batch" = Table.SelectRows(#"IndexedNamesWithBatchID", each ([batchid] = batchid)),
		            #"JsonOutput" = Json.FromValue(#"Batch"),
		            #"OutputText" = "{""names"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonGender" = Json.Document(Web.Contents("https://api.namsor.com/onomastics/api/json/genderList",
				             [
					             Headers = [#"X-Channel-Secret"="63m6Yx0zLNAM33krdm3SORekGn8CFB",#"X-Channel-User"=apiKey],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonGender",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"names"}, {"json.names"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.names"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.names", {"id", "firstName", "lastName", "gender", "scale"}, {"id", "firstName", "lastName", "gender", "scale"})
    in
        #"ExpandedResult";

GenderAPIType = type function (
    optional firstName as (type text meta [
        Documentation.FieldCaption = "First Name",
        Documentation.FieldDescription = "The First Name(s) incuding Middle Name(s)",
        Documentation.SampleValues = {"John", "Maria"}
    ]),
    optional lastName as (type text meta [
        Documentation.FieldCaption = "Last Name",
        Documentation.FieldDescription = "The Family Name / Surname / Last Name(s)",
        Documentation.SampleValues = {"Smith", "Rossini"}
    ]),
    optional countryIso2 as (type text meta [
        Documentation.FieldCaption = "Country (ISO2 code)",
        Documentation.FieldDescription = "Number of times to repeat the message",
        Documentation.SampleValues = {"us","it"}
    ]))
    as table meta [
        Documentation.Name = "NamSor Gender",
        Documentation.LongDescription = "Infer Gender from Name",
        Documentation.Examples = {[
            Description = "Infer likely gender from firstName, lastName",
            Code = "NamSorAPIConnector.Gender(""John"",""Smith"")",
            Result = "male"
        ],[
            Description = "Infer likely gender from firstName, lastName and geographic context",
            Code = "NamSorAPIConnector.Gender(""Elena"",""Rossini"",""it"")",
            Result = "female"
        ]}
    ];


// BUG/ANNOYANCE : when firstName, lastName are not optional - there keeps asking crendentials ... 
GenderImpl = (optional firstName as text, optional lastName as text, optional countryIso2 as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        // TODO test nulls        
        jsonGender = Json.Document(Web.Contents("https://api.namsor.com/onomastics/api/json/gender/" & firstName & "/" & lastName & "/" & countryIso2,
             [
                 Headers = [#"X-Channel-Secret"=client_secret,#"X-Channel-User"=apiKey]
             ]
        )),
         #"genderResult" = jsonGender[gender] //Record.ToTable(jsonGender)
    in
        #"genderResult";

OriginBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have firstName, lastName columns.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional firstNameColumn as (type text meta [
        Documentation.FieldCaption = "First Name Column",
        Documentation.FieldDescription = "The name of column containing : The First Name(s) incuding Middle Name(s)",
        Documentation.SampleValues = {"firstName"}
    ]),
    optional lastNameColumn as (type text meta [
        Documentation.FieldCaption = "Last Name Column",
        Documentation.FieldDescription = "The name of column containing : The Family Name / Surname / Last Name(s)",
        Documentation.SampleValues = {"lastName"}
    ])
    )
    as table meta [
        Documentation.Name = "Append Origin to Table",
        Documentation.LongDescription = "Infer Origin from Name(s) in a Table",
        Documentation.Examples = {[
            Description = "Infer likely Origin from firstName, lastName",
            Code = "NamSorAPIConnector.OriginBatch(""John"",""Smith"")",
            Result = "male"
        ],[
            Description = "Infer likely Origin from firstName, lastName and geographic context",
            Code = "NamSorAPIConnector.OriginBatch(""Elena"",""Rossini"",""it"")",
            Result = "female"
        ]}
    ];

// BUG/ANNOYANCE : when params are not optional - there keeps asking crendentials ... when they are, there is an error after cnnecting
OriginBatchImpl = (optional inputTable as table, optional firstNameColumn as text, optional lastNameColumn as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{firstNameColumn, type text}, {lastNameColumn, type text}}),
        #"Renamed Columns" = Table.RenameColumns(#"Changed Type",{{firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}}),
        #"Removed Other Columns" = Table.SelectColumns(#"Renamed Columns",{"firstName", "lastName"}),
        #"DistinctNames" = Table.Distinct(#"Removed Other Columns"),
        #"DistinctNamesNonNull" = Table.SelectRows(#"DistinctNames", each ([firstName] <> null) and ([lastName] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"DistinctNamesNonNull", "id", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([id]/batch_size)),

        // https://social.technet.microsoft.com/Forums/en-US/0f9fec02-4469-4c56-92ec-00d46b26b3fc/how-to-automateparameterizeloop-power-query?forum=powerquery
        Batch.Results = (batchid) => let 
                    #"Batch" = Table.SelectRows(#"IndexedNamesWithBatchID", each ([batchid] = batchid)),
		            #"JsonOutput" = Json.FromValue(#"Batch"),
		            #"OutputText" = "{""names"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonOrigin" = Json.Document(Web.Contents("https://api.namsor.com/onomastics/api/json/originList",
				             [
					             Headers = [#"X-Channel-Secret"="63m6Yx0zLNAM33krdm3SORekGn8CFB",#"X-Channel-User"=apiKey],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonOrigin",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"names"}, {"json.names"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.names"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.names", {"id", "firstName", "lastName", "country", "countryAlt", "score", "countryFirstName", "countryLastName", "scoreFirstName", "scoreLastName", "subRegion", "region", "topRegion", "countryName", "script"}, {"id", "firstName", "lastName", "country", "countryAlt", "score", "countryFirstName", "countryLastName", "scoreFirstName", "scoreLastName", "subRegion", "region", "topRegion", "countryName", "script"})
    in
        #"ExpandedResult";

 OriginAPIType = type function (
    optional firstName as (type text meta [
        Documentation.FieldCaption = "First Name",
        Documentation.FieldDescription = "The First Name(s) incuding Middle Name(s)",
        Documentation.SampleValues = {"Oleg", "Maria"}
    ]),
    optional lastName as (type text meta [
        Documentation.FieldCaption = "Last Name",
        Documentation.FieldDescription = "The Family Name / Surname / Last Name(s)",
        Documentation.SampleValues = {"Sokolov", "Rossini"}
    ]))
    as table meta [
        Documentation.Name = "NamSor Origin",
        Documentation.LongDescription = "Infer Country Origin from Name",
        Documentation.Examples = {[
            Description = "Infer likely country of origin (ISO2) from firstName, lastName",
            Code = "NamSorAPIConnector.Gender(""Oleg"",""Sokolov"")",
            Result = "ru"
        ],[
            Description = "Infer likely country of origin (ISO2) from firstName, lastName",
            Code = "NamSorAPIConnector.Gender(""Elena"",""Rossini"")",
            Result = "it"
        ]}
    ];

// BUG/ANNOYANCE : when firstName, lastName are not optional - there keeps asking crendentials ... 
OriginImpl = (optional firstName as text, optional lastName as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        // TODO test nulls        
        jsonOrigin = Json.Document(Web.Contents("https://api.namsor.com/onomastics/api/json/origin/" & firstName & "/" & lastName,
             [
                 Headers = [#"X-Channel-Secret"=client_secret,#"X-Channel-User"=apiKey]
             ]
        )),
         #"originResult" = jsonOrigin[country] 
    in
        #"originResult";


DiasporaBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have firstName, lastName columns.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional firstNameColumn as (type text meta [
        Documentation.FieldCaption = "First Name Column",
        Documentation.FieldDescription = "The name of column containing : The First Name(s) incuding Middle Name(s)",
        Documentation.SampleValues = {"firstName"}
    ]),
    optional lastNameColumn as (type text meta [
        Documentation.FieldCaption = "Last Name Column",
        Documentation.FieldDescription = "The name of column containing : The Family Name / Surname / Last Name(s)",
        Documentation.SampleValues = {"lastName"}
    ])
    )
    as table meta [
        Documentation.Name = "Append Diaspora/Ethnicity to Table",
        Documentation.LongDescription = "Infer Diaspora from Name(s) in a Table",
        Documentation.Examples = {[
            Description = "Infer likely Diaspora from firstName, lastName",
            Code = "NamSorAPIConnector.DiasporaBatch(""John"",""Smith"")",
            Result = "British"
        ],[
            Description = "Infer likely Diaspora from firstName, lastName and geographic context",
            Code = "NamSorAPIConnector.DiasporaBatch(""Elena"",""Rossini"")",
            Result = "Italian"
        ]}
    ];

// BUG/ANNOYANCE : when params are not optional - there keeps asking crendentials ... when they are, there is an error after cnnecting
DiasporaBatchImpl = (optional inputTable as table, optional firstNameColumn as text, optional lastNameColumn as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{firstNameColumn, type text}, {lastNameColumn, type text}}),
        #"Renamed Columns" = Table.RenameColumns(#"Changed Type",{{firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}}),
        #"Removed Other Columns" = Table.SelectColumns(#"Renamed Columns",{"firstName", "lastName"}),
        #"DistinctNames" = Table.Distinct(#"Removed Other Columns"),
        #"DistinctNamesNonNull" = Table.SelectRows(#"DistinctNames", each ([firstName] <> null) and ([lastName] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"DistinctNamesNonNull", "id", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([id]/batch_size)),

        // https://social.technet.microsoft.com/Forums/en-US/0f9fec02-4469-4c56-92ec-00d46b26b3fc/how-to-automateparameterizeloop-power-query?forum=powerquery
        Batch.Results = (batchid) => let 
                    #"Batch" = Table.SelectRows(#"IndexedNamesWithBatchID", each ([batchid] = batchid)),
		            #"JsonOutput" = Json.FromValue(#"Batch"),
		            #"OutputText" = "{""names"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonDiaspora" = Json.Document(Web.Contents("https://api.namsor.com/onomastics/api/json/diasporaList",
				             [
					             Headers = [#"X-Channel-Secret"="63m6Yx0zLNAM33krdm3SORekGn8CFB",#"X-Channel-User"=apiKey],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonDiaspora",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"names"}, {"json.names"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.names"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.names", {"id", "firstName", "lastName", "ethno", "ethnoAlt", "geoCountry", "geoCountryAlt", "score", "script"}, {"id", "firstName", "lastName", "ethno", "ethnoAlt", "geoCountry", "geoCountryAlt", "score", "script"})
  in
        #"ExpandedResult";

 DiasporaAPIType = type function (
    optional firstName as (type text meta [
        Documentation.FieldCaption = "First Name",
        Documentation.FieldDescription = "The First Name(s) incuding Middle Name(s)",
        Documentation.SampleValues = {"Oleg", "Maria"}
    ]),
    optional lastName as (type text meta [
        Documentation.FieldCaption = "Last Name",
        Documentation.FieldDescription = "The Family Name / Surname / Last Name(s)",
        Documentation.SampleValues = {"Sokolov", "Rossini"}
    ]))
    as table meta [
        Documentation.Name = "NamSor Diaspora",
        Documentation.LongDescription = "Infer Diaspora/Ethnicity from Name",
        Documentation.Examples = {[
            Description = "Infer likely country of diaspora (ISO2) from firstName, lastName",
            Code = "NamSorAPIConnector.Gender(""Oleg"",""Sokolov"")",
            Result = "Russian"
        ],[
            Description = "Infer likely country of diaspora (ISO2) from firstName, lastName",
            Code = "NamSorAPIConnector.Gender(""Elena"",""Rossini"")",
            Result = "Italian"
        ]}
    ];

// BUG/ANNOYANCE : when firstName, lastName are not optional - there keeps asking crendentials ... 
DiasporaImpl = (optional firstName as text, optional lastName as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        // TODO test nulls        
        jsonDiaspora = Json.Document(Web.Contents("https://api.namsor.com/onomastics/api/json/diaspora/" & firstName & "/" & lastName,
             [
                 Headers = [#"X-Channel-Secret"=client_secret,#"X-Channel-User"=apiKey]
             ]
        )),
         #"diasporaResult" = jsonDiaspora[ethno] 
    in
        #"diasporaResult";


UsageHistoryAPIType = type function (
    optional serviceName as (type text meta [
        Documentation.FieldCaption = "Service Name",
        Documentation.FieldDescription = "The Service Name (gender, origin, ...) ",
        Documentation.SampleValues = {"gender", "origin","diaspora","parse"}
    ]))
    as table meta [
        Documentation.Name = "NamSor API Usage History",
        Documentation.LongDescription = "NamSor API Usage History",
        Documentation.Examples = {[
            Description = "NamSor Gender API Usage History",
            Code = "NamSorAPIConnector.UsageHistory(""gender"")",
            Result = ""
        ],[
            Description = "NamSor Gender API Usage History",
            Code = "NamSorAPIConnector.UsageHistory(""gender"")",
            Result = ""
        ]}
    ];

// BUG/ANNOYANCE : when serviceName is not optional - there keeps asking crendentials ... 
UsageHistoryImpl = (optional serviceName as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        jsonUsageHistory = Json.Document(Web.Contents("https://api.namsor.com/namsor/webresources/management/json/usageHistory/" & serviceName,
             [
                 Headers = [#"X-Channel-Secret"=client_secret,#"X-Channel-User"=apiKey]
             ]
        )),
        #"Converted to Table" = Table.FromList(jsonUsageHistory, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"service", "dateShort", "consumption", "calls"}, {"service", "dateShort", "consumption", "calls"}),
        #"usageHistoryResult" = Table.TransformColumnTypes(#"Expanded Column1",{{"service", type text}, {"dateShort", type date}, {"consumption", Int64.Type}, {"calls", Int64.Type}})
    in
        #"usageHistoryResult";


CurrentUsageAPIType = type function ()
    as table meta [
        Documentation.Name = "NamSor API Current Usage",
        Documentation.LongDescription = "NamSor API Current Usage",
        Documentation.Examples = {[
            Description = "NamSor API Current Usage",
            Code = "NamSorAPIConnector.CurrentUsage()",
            Result = ""
        ]}
    ];

// BUG/ANNOYANCE : when serviceName is not optional - there keeps asking crendentials ... 
CurrentUsageImpl = () as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        jsonCurrentUsage = Json.Document(Web.Contents("https://api.namsor.com/namsor/webresources/management/json/usageCurrent",
             [
                 Headers = [#"X-Channel-Secret"=client_secret,#"X-Channel-User"=apiKey]
             ]
        )),
        #"Converted to Table" = Table.FromList(jsonCurrentUsage, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"planId", "planCreated", "planName", "planStatus", "service", "moneyEstimateToString", "moneyEstimate", "currencyEstimate", "consumption", "description"}, {"planId", "planCreated", "planName", "planStatus", "service", "moneyEstimateToString", "moneyEstimate", "currencyEstimate", "consumption", "description"}),
        #"Current Usage" = Table.TransformColumnTypes(#"Expanded Column1",{{"planId", Int64.Type}, {"planCreated", type datetime}, {"planName", type text}, {"planStatus", type text}, {"service", type text}, {"moneyEstimate", Currency.Type}, {"currencyEstimate", type text}, {"consumption", Int64.Type}})
    in
        #"Current Usage";

// Data Source Kind description
NamSorAPIGenderBatchConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIGenderBatchConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Gender Batch API", "Infer likely gender from a personal name (batch processing, appends several columns)." }
];


// Data Source Kind description
NamSorAPIGenderConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIGenderConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Gender API", "Infer gender from a personal name (appends one column, row by row)." }
];


// Data Source Kind description
NamSorAPIOriginBatchConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIOriginBatchConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Origin Batch API", "Infer likely country of origin from a personal name (batch processing, appends several columns)." }
];


// Data Source Kind description
NamSorAPIOriginConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIOriginConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Origin API", "Infer likely country of origin from a personal name (appends one column, row by row)." }
];


// Data Source Kind description
NamSorAPIDiasporaBatchConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIDiasporaBatchConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Diaspora Batch API", "Infer diaspora/likely ethnicity from a personal name (batch processing, appends several columns)." }
];


// Data Source Kind description
NamSorAPIDiasporaConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIDiasporaConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Diaspora API", "Infer ldiaspora/likely ethnicity from a personal name (appends one column, row by row)." }
];


// Data Source Kind description
NamSorAPIUsageHistoryConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIUsageHistoryConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Usage History API", "Get API access history." }
];

// Data Source Kind description
NamSorAPICurrentUsageConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPICurrentUsageConnector.Publish = [
    Beta = is_beta,
    LearnMoreURL = learn_more_url,
    Category = category,
    ButtonText = { "NamSor Current Usage API", "Get API current access." }
];