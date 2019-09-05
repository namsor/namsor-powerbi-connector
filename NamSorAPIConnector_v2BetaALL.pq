section NamSorAPIConnector;

api_root = Text.FromBinary(Extension.Contents("api_root"));
is_beta = true;
category = "Online Services";
learn_more_url = "https://github.com/namsor/namsor-powerbi-connector";
// batch size for API calls : 100 or 500 (must be strictly less than 1000)
batch_size = 100; 

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

[DataSource.Kind="NamSorAPIParseBatchConnector", Publish="NamSorAPIParseBatchConnector.Publish"]
shared NamSorAPIConnector.ParseBatch = Value.ReplaceType(ParseBatchImpl, ParseBatchAPIType);


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
		            #"JsonOutput" = Json.FromValue(#"Batch"),
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonGender" = Json.Document(Web.Contents("api_root" & "genderBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonGender",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"personalNames"}, {"json.personalNames"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.personalNames"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.personalNames", {"id", "firstName", "lastName", "likelyGender", "genderScale"}, {"id", "firstName", "lastName", "likelyGender", "genderScale"}),
        #"Duplicated FN" = Table.DuplicateColumn(#"ExpandedResult", "firstName", "firstName - Copy"),
        #"Duplicated LN" = Table.DuplicateColumn(#"Duplicated FN", "lastName", "lastName - Copy"),
        #"Merged Columns" = Table.CombineColumns(#"Duplicated LN",{"firstName - Copy", "lastName - Copy"},Combiner.CombineTextByDelimiter("#(tab)", QuoteStyle.None),"fullNameTabJoin")
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
        jsonGender = Json.Document(Web.Contents(api_root & "genderGeo" & "/" & firstName & "/" & lastName & "/" & countryIso2,
             [
                 Headers = [#"X-API-KEY"=apiKey]
             ]
        )),
         #"genderResult" = jsonGender[likelyGender] //Record.ToTable(jsonGender)
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
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonOrigin" = Json.Document(Web.Contents(api_root & "originBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonOrigin",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"personalNames"}, {"json.personalNames"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.personalNames"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.personalNames", {"id", "firstName", "lastName", "countryOrigin", "countryOriginAlt", "score", "regionOrigin", "topRegionOrigin", "subRegionOrigin"}, {"id", "firstName", "lastName", "countryOrigin", "countryOriginAlt", "score", "regionOrigin", "topRegionOrigin", "subRegionOrigin"}),
        #"Duplicated FN" = Table.DuplicateColumn(#"ExpandedResult", "firstName", "firstName - Copy"),
        #"Duplicated LN" = Table.DuplicateColumn(#"Duplicated FN", "lastName", "lastName - Copy"),
        #"Merged Columns" = Table.CombineColumns(#"Duplicated LN",{"firstName - Copy", "lastName - Copy"},Combiner.CombineTextByDelimiter("#(tab)", QuoteStyle.None),"fullNameTabJoin")
    in
        #"Merged Columns";
	

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
        jsonOrigin = Json.Document(Web.Contents(api_root & "origin" & "/" & firstName & "/" & lastName,
             [
                 Headers = [#"X-API-KEY"=apiKey]
             ]
        )),
         #"originResult" = jsonOrigin[countryOrigin] 
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
    ]),
    optional countryIso2 as (type text meta [
        Documentation.FieldCaption = "Country (ISO2 code)",
        Documentation.FieldDescription = "Assumed country of residence",
        Documentation.SampleValues = {"US","IT"}
    ])
    )
    as table meta [
        Documentation.Name = "Append Diaspora/Ethnicity to Table",
        Documentation.LongDescription = "Infer Diaspora from Name(s) in a Table",
        Documentation.Examples = {[
            Description = "Infer likely Diaspora from firstName, lastName and geographic context",
            Code = "NamSorAPIConnector.DiasporaBatch(""Elena"",""Rossini"",""US"")",
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
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonDiaspora" = Json.Document(Web.Contents(api_root & "diasporaBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonDiaspora",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"personalNames"}, {"json.personalNames"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.personalNames"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.personalNames", {"id", "firstName", "lastName", "ethnicity", "ethnicityAlt", "score"}, {"id", "firstName", "lastName", "ethnicity", "ethnicityAlt", "score"}),
        #"Duplicated FN" = Table.DuplicateColumn(#"ExpandedResult", "firstName", "firstName - Copy"),
        #"Duplicated LN" = Table.DuplicateColumn(#"Duplicated FN", "lastName", "lastName - Copy"),
        #"Merged Columns" = Table.CombineColumns(#"Duplicated LN",{"firstName - Copy", "lastName - Copy"},Combiner.CombineTextByDelimiter("#(tab)", QuoteStyle.None),"fullNameTabJoin")
    in
        #"Merged Columns";
	
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
    ]),
    optional countryIso2 as (type text meta [
        Documentation.FieldCaption = "Country (ISO2 code)",
        Documentation.FieldDescription = "Assumed country of residence",
        Documentation.SampleValues = {"US","IT"}
    ])
    )
    as table meta [
        Documentation.Name = "NamSor Diaspora",
        Documentation.LongDescription = "Infer Diaspora/Ethnicity from Name",
        Documentation.Examples = {[
            Description = "Infer likely ethnicity (diaspora) from firstName, lastName, country of residence",
            Code = "NamSorAPIConnector.Gender(""Oleg"",""Sokolov"",""US"")",
            Result = "Russian"
        ]}
    ];

// BUG/ANNOYANCE : when firstName, lastName are not optional - there keeps asking crendentials ... 
DiasporaImpl = (optional firstName as text, optional lastName as text, optional countryIso2 as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        // TODO test nulls        
        jsonDiaspora = Json.Document(Web.Contents(api_root & "diaspora" & "/" & firstName & "/" & lastName & "/" & countryIso2,
             [
                 Headers = [#"X-API-KEY"=apiKey]
             ]
        )),
         #"diasporaResult" = jsonDiaspora[ethnicity] 
    in
        #"diasporaResult";


ParseBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have firstName, lastName columns.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional fullNameColumn as (type text meta [
        Documentation.FieldCaption = "Full Name Column",
        Documentation.FieldDescription = "The name of column containing : The Full Name",
        Documentation.SampleValues = {"firstName"}
    ]),
    optional countryIso2 as (type text meta [
        Documentation.FieldCaption = "Country (ISO2 code)",
        Documentation.FieldDescription = "Assumed country of residence",
        Documentation.SampleValues = {"US","IT"}
    ])
    )
    as table meta [
        Documentation.Name = "Append Parsed Names to Table",
        Documentation.LongDescription = "Infer Parse Names (firstName, lastName) from FullName(s) in a Table",
        Documentation.Examples = {[
            Description = "Infer Parsed Names (firstName, lastName)",
            Code = "NamSorAPIConnector.ParseBatch(""John H. Smith"",""ORDER_FNLN"")",
            Result = "male"
        ],[
            Description = "Infer Parsed Names (firstName, lastName)",
            Code = "NamSorAPIConnector.ParseBatch(""Rossini"",""Elena"",""ORDER_LNFN"")",
            Result = "female"
        ]}
    ];

// BUG/ANNOYANCE : when params are not optional - there keeps asking crendentials ... when they are, there is an error after cnnecting
ParseBatchImpl = (optional inputTable as table, optional fullNameColumn as text, optional countryIso2 as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{fullNameColumn, type text}}),
        #"Renamed Columns" = Table.RenameColumns(#"Changed Type",{{fullNameColumn, "fullName"}}),
        #"Removed Other Columns" = Table.SelectColumns(#"Renamed Columns",{"fullName"}),
        #"DistinctNames" = Table.Distinct(#"Removed Other Columns"),
        #"DistinctNamesNonNull" = Table.SelectRows(#"DistinctNames", each ([fullName] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"DistinctNamesNonNull", "id", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([id]/batch_size)),

        // https://social.technet.microsoft.com/Forums/en-US/0f9fec02-4469-4c56-92ec-00d46b26b3fc/how-to-automateparameterizeloop-power-query?forum=powerquery
        Batch.Results = (batchid) => let 
                    #"Batch" = Table.SelectRows(#"IndexedNamesWithBatchID", each ([batchid] = batchid)),
		            #"JsonOutput" = Json.FromValue(#"Batch"),
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonParse" = Json.Document(Web.Contents(api_root & "parseNameGeoBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonParse",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"personalNames"}, {"json.personalNames"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.personalNames"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.personalNames", {"id", "name", "nameParserType", "score", "firstLastName"}, {"id", "name", "nameParserType", "score", "firstLastName"}),
        #"ExpandedResult2" = Table.ExpandRecordColumn(#"ExpandedResult", "firstLastName", {"firstName", "lastName"}, {"firstName", "lastName"}),
        #"Duplicated FN" = Table.DuplicateColumn(#"ExpandedResult2", "firstName", "firstName - Copy"),
        #"Duplicated LN" = Table.DuplicateColumn(#"Duplicated FN", "lastName", "lastName - Copy"),
        #"Merged Columns" = Table.CombineColumns(#"Duplicated LN",{"firstName - Copy", "lastName - Copy"},Combiner.CombineTextByDelimiter("#(tab)", QuoteStyle.None),"fullNameTabJoin")
    in
        #"Merged Columns";


UsageHistoryAPIType = type function (
    )
    as table meta [
        Documentation.Name = "NamSor API Usage History",
        Documentation.LongDescription = "NamSor API Usage History",
        Documentation.Examples = {[
            Description = "NamSor API Usage History",
            Code = "NamSorAPIConnector.UsageHistory()",
            Result = ""
        ]}
    ];

// BUG/ANNOYANCE : when serviceName is not optional - there keeps asking crendentials ... 
UsageHistoryImpl = (optional serviceName as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        jsonUsageHistory = Json.Document(Web.Contents(api_root & "apiUsageHistoryAggregate",
             [
                 Headers = [#"X-API-KEY"=apiKey]
             ]
        )),
        #"Converted to Table" = Table.FromList(jsonUsageHistory, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    in
        #"Converted to Table";


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
        jsonCurrentUsage = Json.Document(Web.Contents("api_root" & "apiUsage",
             [
                 Headers = [#"X-API-KEY"=apiKey]
             ]
        )),
        #"Converted to Table" = Table.FromList(jsonCurrentUsage, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    in
        #"Converted to Table";

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


// Data Source Kind description
NamSorAPIOriginBatchConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
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
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
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
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
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
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
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
NamSorAPIParseBatchConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIParseBatchConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor Parse Batch API", "Parse a fullName in firstName, lastName (batch processing, appends several columns)." }
];

// Data Source Kind description
NamSorAPIUsageHistoryConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
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
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
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