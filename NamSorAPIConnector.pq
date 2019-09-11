section NamSorAPIConnector;

api_root = Text.FromBinary(Extension.Contents("api_root"));
is_beta = true;
category = "Online Services";
learn_more_url = "https://github.com/namsor/namsor-powerbi-connector";
// batch size for API calls : 100 or 500 (must be strictly less than 1000)
batch_size = 100; 

[DataSource.Kind="NamSorAPIGenderBatchConnector", Publish="NamSorAPIGenderBatchConnector.Publish"]
shared NamSorAPIConnector.GenderBatch = Value.ReplaceType(GenderBatchImpl, GenderBatchAPIType);

[DataSource.Kind="NamSorAPIGenderGeoBatchConnector", Publish="NamSorAPIGenderGeoBatchConnector.Publish"]
shared NamSorAPIConnector.GenderGeoBatch = Value.ReplaceType(GenderGeoBatchImpl, GenderGeoBatchAPIType);

[DataSource.Kind="NamSorAPIGenderConnector", Publish="NamSorAPIGenderConnector.Publish"]
shared NamSorAPIConnector.Gender = Value.ReplaceType(GenderImpl, GenderAPIType);

[DataSource.Kind="NamSorAPIOriginBatchConnector", Publish="NamSorAPIOriginBatchConnector.Publish"]
shared NamSorAPIConnector.OriginBatch = Value.ReplaceType(OriginBatchImpl, OriginBatchAPIType);

[DataSource.Kind="NamSorAPIOriginConnector", Publish="NamSorAPIOriginConnector.Publish"]
shared NamSorAPIConnector.Origin = Value.ReplaceType(OriginImpl, OriginAPIType);

[DataSource.Kind="NamSorAPIDiasporaBatchConnector", Publish="NamSorAPIDiasporaBatchConnector.Publish"]
shared NamSorAPIConnector.DiasporaBatch = Value.ReplaceType(DiasporaBatchImpl, DiasporaBatchAPIType);

[DataSource.Kind="NamSorAPIUSRaceEthnicityBatchConnector", Publish="NamSorAPIUSRaceEthnicityBatchConnector.Publish"]
shared NamSorAPIConnector.USRaceEthnicityBatch = Value.ReplaceType(USRaceEthnicityBatchImpl, USRaceEthnicityBatchAPIType);

[DataSource.Kind="NamSorAPICurrentUsageConnector", Publish="NamSorAPICurrentUsageConnector.Publish"]
shared NamSorAPIConnector.CurrentUsage = Value.ReplaceType(CurrentUsageImpl, CurrentUsageAPIType);

GenderBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have id, firstName, lastName columns.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional idColumn as (type text meta [
        Documentation.FieldCaption = "Unique Index Column",
        Documentation.FieldDescription = "The name of the column containing : Unique Identifier",
        Documentation.SampleValues = {"id"}
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
GenderBatchImpl = (optional inputTable as table, optional idColumn as text, optional firstNameColumn as text, optional lastNameColumn as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{idColumn, type text}, {firstNameColumn, type text}, {lastNameColumn, type text}}),
        #"OriginalInput" = Table.RenameColumns(#"Changed Type",{{idColumn, "id"}, {firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}}),        
        
        // BEGIN BATCH API CALL
        #"IdFnLn" = Table.SelectColumns(#"OriginalInput",{"id", "firstName", "lastName"}),
        #"IdFnLnNonNull" = Table.SelectRows(#"IdFnLn", each ([firstName] <> null) and ([lastName] <> null) and ([id] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"IdFnLnNonNull", "seqId", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([seqId]/batch_size)),

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
        // END BATCH API CALL

        #"Merged Queries" = Table.NestedJoin(#"OriginalInput", {"id"}, #"ExpandedResult", {"id"}, "namsor", JoinKind.LeftOuter),
        #"Expanded API" = Table.ExpandTableColumn(#"Merged Queries", "namsor", {"likelyGender", "genderScale", "probabilityCalibrated", "score"}, {"namsor.likelyGender", "namsor.genderScale", "namsor.probabilityCalibrated", "namsor.score"})
    in
        #"Expanded API";

GenderGeoBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have id, firstName, lastName, countryIso2 columns.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional idColumn as (type text meta [
        Documentation.FieldCaption = "Unique Index Column",
        Documentation.FieldDescription = "The name of the column containing : Unique Identifier",
        Documentation.SampleValues = {"id"}
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
        Documentation.FieldDescription = "The name of column containing : The country of residence",
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
GenderGeoBatchImpl = (optional inputTable as table, optional idColumn as text, optional firstNameColumn as text, optional lastNameColumn as text, optional countryIso2Column as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{idColumn, type text}, {firstNameColumn, type text}, {lastNameColumn, type text}, {countryIso2Column, type text}}),
        #"OriginalInput" = Table.RenameColumns(#"Changed Type",{{idColumn, "id"}, {firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}, {countryIso2Column, "countryIso2"}}),
        
        // BEGIN BATCH API CALL
        #"IdFnLnGeo" = Table.SelectColumns(#"OriginalInput",{"id","firstName", "lastName","countryIso2"}),
        #"IdFnLnGeoNonNull" = Table.SelectRows(#"IdFnLnGeo", each ([firstName] <> null) and ([lastName] <> null) and ([id] <> null) and ([countryIso2] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"IdFnLnGeoNonNull", "seqId", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([seqId]/batch_size)),

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
        // END BATCH API CALL

        #"Merged Queries" = Table.NestedJoin(#"OriginalInput", {"id"}, #"ExpandedResult", {"id"}, "namsor", JoinKind.LeftOuter),
        #"Expanded API" = Table.ExpandTableColumn(#"Merged Queries", "namsor", {"likelyGender", "genderScale", "probabilityCalibrated", "score"}, {"namsor.likelyGender", "namsor.genderScale", "namsor.probabilityCalibrated", "namsor.score"})
    in
        #"Expanded API";

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



OriginBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have id, firstName, lastName columns.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional idColumn as (type text meta [
        Documentation.FieldCaption = "Unique Index Column",
        Documentation.FieldDescription = "The name of the column containing : Unique Identifier",
        Documentation.SampleValues = {"id"}
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
        ]}
    ];

// BUG/ANNOYANCE : when params are not optional - there keeps asking crendentials ... when they are, there is an error after cnnecting
OriginBatchImpl = (optional inputTable as table, optional idColumn as text, optional firstNameColumn as text, optional lastNameColumn as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{idColumn, type text}, {firstNameColumn, type text}, {lastNameColumn, type text}}),
        #"OriginalInput" = Table.RenameColumns(#"Changed Type",{{idColumn, "id"}, {firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}}),        
        
        // BEGIN BATCH API CALL
        #"IdFnLn" = Table.SelectColumns(#"OriginalInput",{"id", "firstName", "lastName"}),
        #"IdFnLnNonNull" = Table.SelectRows(#"IdFnLn", each ([firstName] <> null) and ([lastName] <> null) and ([id] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"IdFnLnNonNull", "seqId", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([seqId]/batch_size)),

        // https://social.technet.microsoft.com/Forums/en-US/0f9fec02-4469-4c56-92ec-00d46b26b3fc/how-to-automateparameterizeloop-power-query?forum=powerquery
        Batch.Results = (batchid) => let 
                    #"Batch" = Table.SelectRows(#"IndexedNamesWithBatchID", each ([batchid] = batchid)),
                    #"BatchClean" = Table.SelectColumns(#"Batch",{"id", "firstName", "lastName"}),
		            #"JsonOutput" = Json.FromValue(#"BatchClean"),
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonOrigin" = Json.Document(Web.Contents(api_root & "originBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey, #"Content-Type"="application/json"],
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
        // END BATCH API CALL

        #"Merged Queries" = Table.NestedJoin(#"OriginalInput", {"id"}, #"ExpandedResult", {"id"}, "namsor", JoinKind.LeftOuter),
        #"Expanded API" = Table.ExpandTableColumn(#"Merged Queries", "namsor", {"countryOrigin", "countryOriginAlt", "score", "regionOrigin", "topRegionOrigin", "subRegionOrigin"}, {"namsor.countryOrigin", "namsor.countryOriginAlt", "namsor.score", "namsor.regionOrigin", "namsor.topRegionOrigin", "namsor.subRegionOrigin"})
    in
        #"Expanded API";

OriginAPIType = type function (
    optional firstName as (type text meta [
        Documentation.FieldCaption = "First Name",
        Documentation.FieldDescription = "The First Name(s) incuding Middle Name(s)",
        Documentation.SampleValues = {"John", "Maria"}
    ]),
    optional lastName as (type text meta [
        Documentation.FieldCaption = "Last Name",
        Documentation.FieldDescription = "The Family Name / Surname / Last Name(s)",
        Documentation.SampleValues = {"Smith", "Rossini"}
    ]))
    as table meta [
        Documentation.Name = "NamSor Origin",
        Documentation.LongDescription = "Infer Origin from Name",
        Documentation.Examples = {[
            Description = "Infer likely Origin from firstName, lastName",
            Code = "NamSorAPIConnector.Origin(""John"",""Smith"")",
            Result = "male"
        ]}
    ];


// BUG/ANNOYANCE : when firstName, lastName are not optional - there keeps asking crendentials ... 
OriginImpl = (optional firstName as text, optional lastName as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        // TODO test nulls        
        jsonOrigin = 
            Json.Document(Web.Contents(api_root & "origin" & "/" & firstName & "/" & lastName,
                [
                 Headers = [#"X-API-KEY"=apiKey]
                ]
            )),
         #"OriginResult" = jsonOrigin[countryOrigin] //Record.ToTable(jsonOrigin)
    in
        #"OriginResult";



DiasporaBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have id, firstName, lastName, countryIso2 columns.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional idColumn as (type text meta [
        Documentation.FieldCaption = "Unique Index Column",
        Documentation.FieldDescription = "The name of the column containing : Unique Identifier",
        Documentation.SampleValues = {"id"}
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
        Documentation.FieldDescription = "The name of column containing : The country of residence",
        Documentation.SampleValues = {"US","IT"}
    ])
    )
    as table meta [
        Documentation.Name = "Append Diaspora to Table",
        Documentation.LongDescription = "Infer Diaspora/Ethnicity from Name(s) in a Table",
        Documentation.Examples = {[
            Description = "Infer likely Diaspora from firstName, lastName and geographic context",
            Code = "NamSorAPIConnector.DiasporaBatch(""Elena"",""Rossini"",""IT"")",
            Result = "Italian"
        ]}
    ];

// BUG/ANNOYANCE : when params are not optional - there keeps asking crendentials ... when they are, there is an error after cnnecting
DiasporaBatchImpl = (optional inputTable as table, optional idColumn as text, optional firstNameColumn as text, optional lastNameColumn as text, optional countryIso2Column as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{idColumn, type text}, {firstNameColumn, type text}, {lastNameColumn, type text}, {countryIso2Column, type text}}),
        #"OriginalInput" = Table.RenameColumns(#"Changed Type",{{idColumn, "id"}, {firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}, {countryIso2Column, "countryIso2"}}),
        
        // BEGIN BATCH API CALL
        #"IdFnLnGeo" = Table.SelectColumns(#"OriginalInput",{"id","firstName", "lastName","countryIso2"}),
        #"IdFnLnGeoNonNull" = Table.SelectRows(#"IdFnLnGeo", each ([firstName] <> null) and ([lastName] <> null) and ([id] <> null) and ([countryIso2] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"IdFnLnGeoNonNull", "seqId", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([seqId]/batch_size)),

        // https://social.technet.microsoft.com/Forums/en-US/0f9fec02-4469-4c56-92ec-00d46b26b3fc/how-to-automateparameterizeloop-power-query?forum=powerquery
        Batch.Results = (batchid) => let 
                    #"Batch" = Table.SelectRows(#"IndexedNamesWithBatchID", each ([batchid] = batchid)),
                    #"BatchClean" = Table.SelectColumns(#"Batch",{"id", "firstName", "lastName", "countryIso2" }),
		            #"JsonOutput" = Json.FromValue(#"BatchClean"),
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonDiaspora" = Json.Document(Web.Contents(api_root & "diasporaBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey, #"Content-Type"="application/json"],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonDiaspora",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"personalNames"}, {"json.personalNames"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.personalNames"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.personalNames", {"id", "firstName", "lastName", "ethnicity", "ethnicityAlt", "countryIso2", "score"}, {"id", "firstName", "lastName", "ethnicity", "ethnicityAlt", "countryIso2", "score"}),
        // END BATCH API CALL

        #"Merged Queries" = Table.NestedJoin(#"OriginalInput", {"id"}, #"ExpandedResult", {"id"}, "namsor", JoinKind.LeftOuter),
        #"Expanded API" = Table.ExpandTableColumn(#"Merged Queries", "namsor", {"ethnicity", "ethnicityAlt", "score"}, {"namsor.ethnicity", "namsor.ethnicityAlt", "namsor.score"})
    in
        #"Expanded API";

USRaceEthnicityBatchAPIType = type function (
    optional inputTable as (type table meta [
        Documentation.FieldCaption = "Input Table",
        Documentation.FieldDescription = "The input table must have id, firstName, lastName columns - all US names.",
        Documentation.SampleValues = {"myCustomerTable"}
    ]),
    optional idColumn as (type text meta [
        Documentation.FieldCaption = "Unique Index Column",
        Documentation.FieldDescription = "The name of the column containing : Unique Identifier",
        Documentation.SampleValues = {"id"}
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
        Documentation.Name = "Append US Race/Ethnicity to Table",
        Documentation.LongDescription = "Infer USRaceEthnicity from Name(s) in a Table with US names.",
        Documentation.Examples = {[
            Description = "Infer likely USRaceEthnicity from firstName, lastName",
            Code = "NamSorAPIConnector.USRaceEthnicityBatch(""Jing"",""Guo"")",
            Result = "Asian"
        ]}
    ];

// BUG/ANNOYANCE : when params are not optional - there keeps asking crendentials ... when they are, there is an error after cnnecting
USRaceEthnicityBatchImpl = (optional inputTable as table, optional idColumn as text, optional firstNameColumn as text, optional lastNameColumn as text) as table =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        #"Changed Type" = Table.TransformColumnTypes(inputTable,{{idColumn, type text}, {firstNameColumn, type text}, {lastNameColumn, type text}}),
        #"OriginalInput" = Table.RenameColumns(#"Changed Type",{{idColumn, "id"}, {firstNameColumn, "firstName"}, {lastNameColumn, "lastName"}}),        
        #"OriginalInputUS" = Table.AddColumn(#"OriginalInput", "countryIso2", each "US"),

        // BEGIN BATCH API CALL
        #"IdFnLn" = Table.SelectColumns(#"OriginalInputUS",{"id", "firstName", "lastName", "countryIso2"}),
        #"IdFnLnNonNull" = Table.SelectRows(#"IdFnLn", each ([firstName] <> null) and ([lastName] <> null) and ([id] <> null)),
        #"IndexedNames" = Table.AddIndexColumn(#"IdFnLnNonNull", "seqId", 1, 1),
        #"IndexedNamesWithBatchID" = Table.AddColumn(#"IndexedNames", "batchid", each Number.RoundDown([seqId]/batch_size)),

        // https://social.technet.microsoft.com/Forums/en-US/0f9fec02-4469-4c56-92ec-00d46b26b3fc/how-to-automateparameterizeloop-power-query?forum=powerquery
        Batch.Results = (batchid) => let 
                    #"Batch" = Table.SelectRows(#"IndexedNamesWithBatchID", each ([batchid] = batchid)),
                    #"BatchClean" = Table.SelectColumns(#"Batch",{"id", "firstName", "lastName"}),
		            #"JsonOutput" = Json.FromValue(#"BatchClean"),
		            #"OutputText" = "{""personalNames"":" & Text.FromBinary(#"JsonOutput") & "}",
		            #"jsonUSRaceEthnicity" = Json.Document(Web.Contents(api_root & "usRaceEthnicityBatch",
				             [
					             Headers = [#"X-API-KEY"=apiKey, #"Content-Type"="application/json"],
					             Content=Text.ToBinary(#"OutputText")
				             ]
			            ))
                    in
                        #"jsonUSRaceEthnicity",

        #"Grouped Rows" = Table.Group(#"IndexedNamesWithBatchID", {"batchid"}, {{"Count", each Table.RowCount(_), type number}}),
        #"Batched" = Table.AddColumn(#"Grouped Rows", "json", each Batch.Results([batchid])),
        #"Expanded json" = Table.ExpandRecordColumn(#"Batched", "json", {"personalNames"}, {"json.personalNames"}),
        #"Expanded json.names" = Table.ExpandListColumn(#"Expanded json", "json.personalNames"),
        #"ExpandedResult" = Table.ExpandRecordColumn(#"Expanded json.names", "json.personalNames", {"id", "firstName", "lastName", "raceEthnicity", "raceEthnicityAlt", "score"}, {"id", "firstName", "lastName", "raceEthnicity", "raceEthnicityAlt", "score"}),
        // END BATCH API CALL

        #"Merged Queries" = Table.NestedJoin(#"OriginalInput", {"id"}, #"ExpandedResult", {"id"}, "namsor", JoinKind.LeftOuter),
        #"Expanded API" = Table.ExpandTableColumn(#"Merged Queries", "namsor", {"raceEthnicity", "raceEthnicityAlt", "score"}, {"namsor.raceEthnicity", "namsor.raceEthnicityAlt", "namsor.score"})
    in
        #"Expanded API";


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
        jsonCurrentUsage = Json.Document(Web.Contents(api_root & "apiUsage",
             [
                 Headers = [#"X-API-KEY"=apiKey]
             ]
        )),
        #"toTable" =  Record.ToTable(jsonCurrentUsage)
    in
        #"toTable";


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
    ButtonText = { "NamSor Origin Batch API", "Infer likely Origin from a personal name (batch processing, appends several columns)." }
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
    ButtonText = { "NamSor Origin API", "Infer Origin from a personal name (appends one column, row by row)." }
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
    ButtonText = { "NamSor Diaspora Batch API", "Infer likely Diaspora / Ethnicity from a personal name (batch processing, appends several columns) with known residence country." }
];



// Data Source Kind description
NamSorAPIUSRaceEthnicityBatchConnector = [
    Authentication = [
        Key = [
            KeyLabel = "NamSor API Key (ex: #################912d27cdbacf7lc)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIUSRaceEthnicityBatchConnector.Publish = [
    Beta = is_beta,
    Category = category,
    ButtonText = { "NamSor USRaceEthnicity Batch API", "Infer likely USRaceEthnicity from a personal name (batch processing, appends several columns)." }
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