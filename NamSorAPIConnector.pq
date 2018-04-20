section NamSorAPIConnector;

client_secret = Text.FromBinary(Extension.Contents("client_secret"));

[DataSource.Kind="NamSorAPIConnector", Publish="NamSorAPIConnector.Publish"]
shared NamSorAPIConnector.Gender = Value.ReplaceType(GenderImpl, GenderAPIType);

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

GenderImpl = (optional firstName as text, optional lastName as text, optional countryIso2 as text) as text =>
    let
        apiKey = Extension.CurrentCredential()[Key],
        jsonGender = Json.Document(Web.Contents("https://api.namsor.com/onomastics/api/json/gender/" & firstName & "/" & lastName,
             [
                 Headers = [#"X-Channel-Secret"=client_secret,#"X-Channel-User"=apiKey]
             ]
        )),
         #"genderResult" = jsonGender[gender] //Record.ToTable(jsonGender)
    in
        #"genderResult";

// Data Source Kind description
NamSorAPIConnector = [
    Authentication = [
        
        Key = [
            KeyLabel = "NamSor API Key (ex: namsor.com/john.smith@company.com/123456)",
            Label = "NamSor API Key"
        ]
    ],
    Label = "NamSor API"
];

// Data Source UI publishing description
NamSorAPIConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { "NamSor API", "Infer gender or cultural origin/ethnicity from a personal name." }
];
