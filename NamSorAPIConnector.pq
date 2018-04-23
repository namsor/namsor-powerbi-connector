section NamSorAPIConnector;

client_secret = Text.FromBinary(Extension.Contents("client_secret"));

[DataSource.Kind="NamSorAPIGenderConnector", Publish="NamSorAPIGenderConnector.Publish"]
shared NamSorAPIConnector.Gender = Value.ReplaceType(GenderImpl, GenderAPIType);
[DataSource.Kind="NamSorAPIOriginConnector", Publish="NamSorAPIOriginConnector.Publish"]
shared NamSorAPIConnector.Origin = Value.ReplaceType(OriginImpl, OriginAPIType);
[DataSource.Kind="NamSorAPIUsageHistoryConnector", Publish="NamSorAPIUsageHistoryConnector.Publish"]
shared NamSorAPIConnector.UsageHistory = Value.ReplaceType(UsageHistoryImpl, UsageHistoryAPIType);
[DataSource.Kind="NamSorAPICurrentUsageConnector", Publish="NamSorAPICurrentUsageConnector.Publish"]
shared NamSorAPIConnector.CurrentUsage = Value.ReplaceType(CurrentUsageImpl, CurrentUsageAPIType);

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
NamSorAPIOriginConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { "NamSor Origin API", "Infer likely country of origin from a personal name." }
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
NamSorAPIGenderConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { "NamSor Gender API", "Infer gender from a personal name." }
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
    Beta = true,
    Category = "Other",
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
    Beta = true,
    Category = "Other",
    ButtonText = { "NamSor Current Usage API", "Get API current access." }
];