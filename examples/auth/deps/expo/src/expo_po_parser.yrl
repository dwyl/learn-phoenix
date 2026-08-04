Nonterminals
  grammar
  obsolete_pluralization
  obsolete_pluralizations
  obsolete_plural_message
  obsolete_singular_message
  only_comments
  pluralization
  pluralizations
  plural_message
  singular_message
  message
  messages
  message_meta.
Terminals
  comment
  msgctxt
  msgid
  msgid_plural
  msgstr
  obsolete_msgctxt
  obsolete_msgid
  obsolete_msgid_plural
  obsolete_msgstr
  plural_form
  previous
  str_lines.
Rootsymbol grammar.
Endsymbol '$end'.

grammar ->
  only_comments : {only_comments, '$1'}.
grammar ->
  messages : {messages, '$1'}.
grammar ->
  '$empty' : empty.

only_comments ->
  comment only_comments : [extract_simple_token('$1') | '$2'].
only_comments ->
  comment : [extract_simple_token('$1')].

messages ->
  message messages : ['$1' | '$2'].
messages ->
  message : ['$1'].

message ->
  obsolete_singular_message : '$1'.
message ->
  singular_message : '$1'.
message ->
  obsolete_plural_message : '$1'.
message ->
  plural_message : '$1'.

singular_message ->
  message_meta msgid str_lines msgstr str_lines : to_singular_message(
    [
      {msgid, extract_simple_token('$3')},
      {msgstr, extract_simple_token('$5')}
      | group_meta('$1')
    ], [
      {msgid, extract_line('$2')},
      {msgstr, extract_line('$4')}
    ]
  ).
singular_message ->
  message_meta msgctxt str_lines msgid str_lines msgstr str_lines : to_singular_message(
    [
      {msgctxt, extract_simple_token('$3')},
      {msgid, extract_simple_token('$5')},
      {msgstr, extract_simple_token('$7')}
      | group_meta('$1')
    ],
    [
      {msgctxt, extract_line('$2')},
      {msgid, extract_line('$4')},
      {msgstr, extract_line('$6')}
    ]
  ).

obsolete_singular_message ->
  message_meta obsolete_msgid str_lines obsolete_msgstr str_lines : to_singular_message(
    [
      {obsolete, true},
      {msgid, extract_simple_token('$3')},
      {msgstr, extract_simple_token('$5')}
      | group_meta('$1')
    ], [
      {msgid, extract_line('$2')},
      {msgstr, extract_line('$4')}
    ]
  ).
obsolete_singular_message ->
  message_meta obsolete_msgctxt str_lines obsolete_msgid str_lines obsolete_msgstr str_lines : to_singular_message(
    [
      {obsolete, true},
      {msgctxt, extract_simple_token('$3')},
      {msgid, extract_simple_token('$5')},
      {msgstr, extract_simple_token('$7')}
      | group_meta('$1')
    ],
    [
      {msgctxt, extract_line('$2')},
      {msgid, extract_line('$4')},
      {msgstr, extract_line('$6')}
    ]
  ).

plural_message ->
  message_meta msgid str_lines msgid_plural str_lines pluralizations :
  {Pluralizations, PluralLineInformation} = split_msgstr('$6'),
  to_plural_message(
    [
      {msgid, extract_simple_token('$3')},
      {msgid_plural, extract_simple_token('$5')},
      {msgstr, maps:from_list(Pluralizations)}
      | group_meta('$1')
    ],
    [
      {msgid, extract_line('$2')},
      {msgid_plural, extract_line('$4')} | PluralLineInformation
    ]
  ).
plural_message ->
  message_meta msgctxt str_lines msgid str_lines msgid_plural str_lines pluralizations :
  {Pluralizations, PluralLineInformation} = split_msgstr('$8'),
  to_plural_message(
    [
      {msgctxt, extract_simple_token('$3')},
      {msgid, extract_simple_token('$5')},
      {msgid_plural, extract_simple_token('$7')},
      {msgstr, maps:from_list(Pluralizations)}
      | group_meta('$1')
    ],
    [
      {msgctx, extract_line('$2')},
      {msgid, extract_line('$4')},
      {msgid_plural, extract_line('$6')}
      | PluralLineInformation
    ]
  ).

obsolete_plural_message ->
  message_meta obsolete_msgid str_lines obsolete_msgid_plural str_lines obsolete_pluralizations :
  {Pluralizations, PluralLineInformation} = split_msgstr('$6'),
  to_plural_message(
    [
      {obsolete, true},
      {msgid, extract_simple_token('$3')},
      {msgid_plural, extract_simple_token('$5')},
      {msgstr, maps:from_list(Pluralizations)}
      | group_meta('$1')
    ],
    [
      {msgid, extract_line('$2')},
      {msgid_plural, extract_line('$4')}
      | PluralLineInformation
    ]
  ).
obsolete_plural_message ->
  message_meta obsolete_msgctxt str_lines obsolete_msgid str_lines obsolete_msgid_plural str_lines obsolete_pluralizations :
  {Pluralizations, PluralLineInformation} = split_msgstr('$8'),
  to_plural_message(
    [
      {obsolete, true},
      {msgctxt, extract_simple_token('$3')},
      {msgid, extract_simple_token('$5')},
      {msgid_plural, extract_simple_token('$7')},
      {msgstr, maps:from_list(Pluralizations)}
      | group_meta('$1')
    ],
    [
      {msgctx, extract_line('$2')},
      {msgid, extract_line('$4')},
      {msgid_plural, extract_line('$6')}
      | PluralLineInformation
    ]
  ).

pluralizations ->
  pluralization : ['$1'].
pluralizations ->
  pluralization pluralizations : ['$1'|'$2'].

obsolete_pluralizations ->
  obsolete_pluralization : ['$1'].
obsolete_pluralizations ->
  obsolete_pluralization obsolete_pluralizations : ['$1' | '$2'].

pluralization ->
  msgstr plural_form str_lines : {extract_simple_token('$2'), extract_simple_token('$3'), extract_line('$2')}.

obsolete_pluralization ->
  obsolete_msgstr plural_form str_lines : {extract_simple_token('$2'), extract_simple_token('$3'), extract_line('$2')}.

message_meta ->
  '$empty': [].
message_meta ->
  comment message_meta : [
    {comments, extract_simple_token('$1')}
    | '$2'
  ].
message_meta ->
  previous msgctxt str_lines previous msgid str_lines previous msgid_plural str_lines message_meta : [
    {previous_messages, to_plural_message(
      [
        {msgctxt, extract_simple_token('$3')},
        {msgid, extract_simple_token('$6')},
        {msgid_plural, extract_simple_token('$9')}
      ],
      [
        {msgctxt, extract_line('$2')},
        {msgid, extract_line('$5')},
        {msgid_plural, extract_line('$8')}
      ]
    )} | '$10'
  ].
message_meta ->
  previous msgid str_lines previous msgid_plural str_lines message_meta : [
    {previous_messages, to_plural_message(
      [{msgid, extract_simple_token('$3')}, {msgid_plural, extract_simple_token('$6')}],
      [{msgid, extract_line('$2')}, {msgid_plural, extract_line('$5')}]
    )} | '$7'
  ].
message_meta ->
  previous msgctxt str_lines previous msgid str_lines message_meta : [
    {previous_messages, to_singular_message(
      [{msgctxt, extract_simple_token('$3')}, {msgid, extract_simple_token('$6')}],
      [{msgctxt, extract_line('$2')}, {msgid, extract_line('$5')}]
    )} | '$7'
  ].
message_meta ->
  previous msgid str_lines message_meta : [
    {previous_messages, to_singular_message(
      [{msgid, extract_simple_token('$3')}],
      [{msgid, extract_line('$2')}]
    )} | '$4'
  ].

Erlang code.

extract_simple_token({_Token, _Line, Value}) ->
  Value.

extract_line({_Token, Line}) ->
  Line;
extract_line({_Token, Line, _Value}) ->
  Line.

to_singular_message(Fields, LineNumbers) ->
  'Elixir.Kernel':struct(
    'Elixir.Expo.Message.Singular',
    Fields ++ [{'__meta__', #{source_line => maps:from_list(LineNumbers)}}]
  ).

to_plural_message(Fields, LineNumbers) ->
  'Elixir.Kernel':struct(
    'Elixir.Expo.Message.Plural',
    Fields ++ [{'__meta__', #{source_line => maps:from_list(LineNumbers)}}]
  ).

split_msgstr(Pluralizations) ->
  {
    lists:map(fun({PluralForm, Message, _LineNumber}) -> {PluralForm, Message} end, Pluralizations),
    lists:map(fun({PluralForm, _Message, LineNumber}) -> {{msgstr, PluralForm}, LineNumber} end, Pluralizations)
  }.

group_meta(MetaFields) ->
  maps:to_list(
    % Use maps:groups_from_list when supporting OTP >= 25 exclusively
    lists:foldr(
      fun({Key, Value}, Acc) ->
        maps:update_with(Key, fun(Cur) -> [Value | Cur] end, [Value], Acc)
      end,
      #{},
      MetaFields
    )
  ).
