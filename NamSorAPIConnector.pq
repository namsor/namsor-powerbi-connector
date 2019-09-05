section NamSorAPIConnector;

api_root = Text.FromBinary(Extension.Contents("api_root"));
is_beta = true;
category = "Online Services";
learn_more_url = "https://github.com/namsor/namsor-powerbi-connector";
// batch size for API calls : 100 or 500 (must be strictly less than 1000)
batch_size = 100; 

[DataSource.Kind="NamSorAPIGenderBatchConnector", Publish="NamSorAPIGenderBatchConnector.Publish"]
shared NamSorAPIConnector.GenderBatch = Value.ReplaceType(GenderBatchImpl, GenderBatchAPIType);

[DataSource.Kind="NamSorAPIGenderGeoBatchConnector", Publish="NamSorAPIGenderBatchConnector.Publish"]
shared NamSorAPIConnector.GenderGeoBatch = Value.ReplaceType(GenderGeoBatchImpl, GenderGeoBatchAPIType);

[DataSource.Kind="NamSorAPIGenderConnector", Publish="NamSorAPIGenderConnector.Publish"]
shared NamSorAPIConnector.Gender = Value.ReplaceType(GenderImpl, GenderAPIType);

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
            Code = "NamSorAPIConnector.GenderBatch(""Elena"",""Rossini"",""IT"")",
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
                    #"BatchClean" = Table.SelectColumns(#"Batch",{"id", "firstName", "lastName"}),
		            #"JsonOutput" = Json.FromValue(#"BatchClean"),
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonGender" = Json.Document(Web.Contents(api_root & "genderBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey, #"Content-Type"="application/json"],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonGender",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"personalNames"}, {"json.personalNames"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.personalNames"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.personalNames", {"id", "firstName", "lastName", "likelyGender", "genderScale", "probabilityCalibrated", "score"}, {"id", "firstName", "lastName", "likelyGender", "genderScale", "probabilityCalibrated", "score"}),
        #"Duplicated FN" = Table.DuplicateColumn(#"ExpandedResult", "firstName", "firstName - Copy"),
        #"Duplicated LN" = Table.DuplicateColumn(#"Duplicated FN", "lastName", "lastName - Copy"),
        #"Merged Columns" = Table.CombineColumns(#"Duplicated LN",{"firstName - Copy", "lastName - Copy"},Combiner.CombineTextByDelimiter("#(tab)", QuoteStyle.None),"fullNameTabJoin")
    in
        #"Merged Columns";

GenderGeoBatchAPIType = type function (
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
    ]),
    optional countryIso2Column as (type text meta [
        Documentation.FieldCaption = "Country (ISO2 code) Column",
        Documentation.FieldDescription = "Assumed country of residence",
        Documentation.SampleValues = {"US","IT"}
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
            Code = "NamSorAPIConnector.GenderBatch(""Elena"",""Rossini"",""IT"")",
            Result = "female"
        ]}
    ];

// BUG/ANNOYANCE : when params are not optional - there keeps asking crendentials ... when they are, there is an error after cnnecting
GenderGeoBatchImpl = (optional inputTable as table, optional firstNameColumn as text, optional lastNameColumn as text, optional countryIso2Column as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{firstNameColumn, type text}, {lastNameColumn, type text}, {countryIso2Column, type text}}),
        #"Renamed Columns" = Table.RenameColumns(#"Changed Type",{{firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}, {countryIso2Column, "countryIso2"}}),
        #"Removed Other Columns" = Table.SelectColumns(#"Renamed Columns",{"firstName", "lastName","countryIso2"}),
        #"DistinctNames" = Table.Distinct(#"Removed Other Columns"),
        #"DistinctNamesNonNull" = Table.SelectRows(#"DistinctNames", each ([firstName] <> null) and ([lastName] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"DistinctNamesNonNull", "id", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([id]/batch_size)),

        // https://social.technet.microsoft.com/Forums/en-US/0f9fec02-4469-4c56-92ec-00d46b26b3fc/how-to-automateparameterizeloop-power-query?forum=powerquery
        Batch.Results = (batchid) => let 
                    #"Batch" = Table.SelectRows(#"IndexedNamesWithBatchID", each ([batchid] = batchid)),
                    #"BatchClean" = Table.SelectColumns(#"Batch",{"id", "firstName", "lastName", "countryIso2" }),
		            #"JsonOutput" = Json.FromValue(#"BatchClean"),
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonGender" = Json.Document(Web.Contents(api_root & "genderGeoBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey, #"Content-Type"="application/json"],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonGender",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"personalNames"}, {"json.personalNames"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.personalNames"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.personalNames", {"id", "firstName", "lastName", "likelyGender", "genderScale", "probabilityCalibrated", "score"}, {"id", "firstName", "lastName", "likelyGender", "genderScale", "probabilityCalibrated", "score"}),
        #"Duplicated FN" = Table.DuplicateColumn(#"ExpandedResult", "firstName", "firstName - Copy"),
        #"Duplicated LN" = Table.DuplicateColumn(#"Duplicated FN", "lastName", "lastName - Copy"),
        #"Duplicated Cntry" = Table.DuplicateColumn(#"Duplicated LN", "countryIso2", "countryIso2 - Copy"),
        #"Merged Columns" = Table.CombineColumns(#"Duplicated Cntry",{"firstName - Copy", "lastName - Copy", "countryIso2 - Copy"},Combiner.CombineTextByDelimiter("#(tab)", QuoteStyle.None),"fullNameTabCntryJoin")
    in
        #"Merged Columns";


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
        Documentation.FieldDescription = "Assumed country of residence",
        Documentation.SampleValues = {"US","IT"}
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
            Code = "NamSorAPIConnector.Gender(""Elena"",""Rossini"",""IT"")",
            Result = "female"
        ]}
    ];


// BUG/ANNOYANCE : when firstName, lastName are not optional - there keeps asking crendentials ... 
GenderImpl = (optional firstName as text, optional lastName as text, optional countryIso2 as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        // TODO test nulls        
        jsonGender = 
            if countryIso2 = null or countryIso2 = "" or countryIso2 = " " then
            Json.Document(Web.Contents(api_root & "gender" & "/" & firstName & "/" & lastName,
                [
                 Headers = [#"X-API-KEY"=apiKey]
                ]
            ))
            else 
            Json.Document(Web.Contents(api_root & "genderGeo" & "/" & firstName & "/" & lastName & "/" & countryIso2,
                [
                 Headers = [#"X-API-KEY"=apiKey]
                ]
            )),
         #"genderResult" = jsonGender[likelyGender] //Record.ToTable(jsonGender)
    in
        #"genderResult";

// Data Source Kind description
NamSorAPIGenderBatchConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
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
NamSorAPIGenderGeoBatchConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIGenderGeoBatchConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Gender Geo Batch API", "Infer likely gender from a personal name (batch processing, appends several columns) with known residence country." }
];

// Data Source Kind description
NamSorAPIGenderConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
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

