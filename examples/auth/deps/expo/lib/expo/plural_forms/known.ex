defmodule Expo.PluralForms.Known do
  @moduledoc false

  # Extracted and adapted from
  # https://github.com/elixir-gettext/gettext/blob/600e4630fb7db514d464f92e2069a138cf9c68a1/lib/gettext/plural.ex

  known_plural_forms =
    """
    ach,   Acholi,                nplurals=2; plural=(n > 1);
    af,    Afrikaans,             nplurals=2; plural=(n != 1);
    ak,    Akan,                  nplurals=2; plural=(n > 1);
    am,    Amharic,               nplurals=2; plural=(n > 1);
    an,    Aragonese,             nplurals=2; plural=(n != 1);
    anp,   Angika,                nplurals=2; plural=(n != 1);
    ar,    Arabic,                nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5);
    arn,   Mapudungun,            nplurals=2; plural=(n > 1);
    as,    Assamese,              nplurals=2; plural=(n != 1);
    ast,   Asturian,              nplurals=2; plural=(n != 1);
    ay,    Aymará,                nplurals=1; plural=0;
    az,    Azerbaijani,           nplurals=2; plural=(n != 1);
    be,    Belarusian,            nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);
    bg,    Bulgarian,             nplurals=2; plural=(n != 1);
    bn,    Bengali,               nplurals=2; plural=(n != 1);
    bo,    Tibetan,               nplurals=1; plural=0;
    br,    Breton,                nplurals=2; plural=(n > 1);
    brx,   Bodo,                  nplurals=2; plural=(n != 1);
    bs,    Bosnian,               nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);
    ca,    Catalan,               nplurals=2; plural=(n != 1);
    cgg,   Chiga,                 nplurals=1; plural=0;
    cs,    Czech,                 nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;
    csb,   Kashubian,             nplurals=3; plural=(n==1) ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2;
    cy,    Welsh,                 nplurals=4; plural=(n==1) ? 0 : (n==2) ? 1 : (n != 8 && n != 11) ? 2 : 3;
    da,    Danish,                nplurals=2; plural=(n != 1);
    de,    German,                nplurals=2; plural=(n != 1);
    doi,   Dogri,                 nplurals=2; plural=(n != 1);
    dz,    Dzongkha,              nplurals=1; plural=0;
    el,    Greek,                 nplurals=2; plural=(n != 1);
    en,    English,               nplurals=2; plural=(n != 1);
    eo,    Esperanto,             nplurals=2; plural=(n != 1);
    es,    Spanish,               nplurals=2; plural=(n != 1);
    es_AR, Argentinean Spanish,   nplurals=2; plural=(n != 1);
    et,    Estonian,              nplurals=2; plural=(n != 1);
    eu,    Basque,                nplurals=2; plural=(n != 1);
    fa,    Persian,               nplurals=2; plural=(n > 1);
    ff,    Fulah,                 nplurals=2; plural=(n != 1);
    fi,    Finnish,               nplurals=2; plural=(n != 1);
    fil,   Filipino,              nplurals=2; plural=(n > 1);
    fo,    Faroese,               nplurals=2; plural=(n != 1);
    fr,    French,                nplurals=2; plural=(n > 1);
    fur,   Friulian,              nplurals=2; plural=(n != 1);
    fy,    Frisian,               nplurals=2; plural=(n != 1);
    ga,    Irish,                 nplurals=5; plural=n==1 ? 0 : n==2 ? 1 : (n>2 && n<7) ? 2 :(n>6 && n<11) ? 3 : 4;
    gd,    Scottish Gaelic,       nplurals=4; plural=(n==1 || n==11) ? 0 : (n==2 || n==12) ? 1 : (n > 2 && n < 20) ? 2 : 3;
    gl,    Galician,              nplurals=2; plural=(n != 1);
    gu,    Gujarati,              nplurals=2; plural=(n != 1);
    gun,   Gun,                   nplurals=2; plural=(n > 1);
    ha,    Hausa,                 nplurals=2; plural=(n != 1);
    he,    Hebrew,                nplurals=2; plural=(n != 1);
    hi,    Hindi,                 nplurals=2; plural=(n != 1);
    hne,   Chhattisgarhi,         nplurals=2; plural=(n != 1);
    hr,    Croatian,              nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);
    hu,    Hungarian,             nplurals=2; plural=(n != 1);
    hy,    Armenian,              nplurals=2; plural=(n != 1);
    ia,    Interlingua,           nplurals=2; plural=(n != 1);
    id,    Indonesian,            nplurals=1; plural=0;
    is,    Icelandic,             nplurals=2; plural=(n%10!=1 || n%100==11);
    it,    Italian,               nplurals=2; plural=(n != 1);
    ja,    Japanese,              nplurals=1; plural=0;
    jbo,   Lojban,                nplurals=1; plural=0;
    jv,    Javanese,              nplurals=2; plural=(n != 0);
    ka,    Georgian,              nplurals=1; plural=0;
    kk,    Kazakh,                nplurals=2; plural=(n != 1);
    kl,    Greenlandic,           nplurals=2; plural=(n != 1);
    km,    Khmer,                 nplurals=1; plural=0;
    kn,    Kannada,               nplurals=2; plural=(n != 1);
    ko,    Korean,                nplurals=1; plural=0;
    ku,    Kurdish,               nplurals=2; plural=(n != 1);
    kw,    Cornish,               nplurals=4; plural=(n==1) ? 0 : (n==2) ? 1 : (n == 3) ? 2 : 3;
    ky,    Kyrgyz,                nplurals=2; plural=(n != 1);
    lb,    Letzeburgesch,         nplurals=2; plural=(n != 1);
    ln,    Lingala,               nplurals=2; plural=(n > 1);
    lo,    Lao,                   nplurals=1; plural=0;
    lt,    Lithuanian,            nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && (n%100<10 || n%100>=20) ? 1 : 2);
    lv,    Latvian,               nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n != 0 ? 1 : 2);
    mai,   Maithili,              nplurals=2; plural=(n != 1);
    me,    Montenegro,            nplurals=3; plural=n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2;
    mfe,   Mauritian Creole,      nplurals=2; plural=(n > 1);
    mg,    Malagasy,              nplurals=2; plural=(n > 1);
    mi,    Maori,                 nplurals=2; plural=(n > 1);
    mk,    Macedonian,            nplurals=3; plural=n%10==1 ? 0 : n%10==2 ? 1 : 2;
    ml,    Malayalam,             nplurals=2; plural=(n != 1);
    mn,    Mongolian,             nplurals=2; plural=(n != 1);
    mni,   Manipuri,              nplurals=2; plural=(n != 1);
    mnk,   Mandinka,              nplurals=3; plural=(n==0 ? 0 : n==1 ? 1 : 2);
    mr,    Marathi,               nplurals=2; plural=(n != 1);
    ms,    Malay,                 nplurals=1; plural=0;
    mt,    Maltese,               nplurals=4; plural=(n==1 ? 0 : n==0 || ( n%100>1 && n%100<11) ? 1 : (n%100>10 && n%100<20 ) ? 2 : 3);
    my,    Burmese,               nplurals=1; plural=0;
    nah,   Nahuatl,               nplurals=2; plural=(n != 1);
    nap,   Neapolitan,            nplurals=2; plural=(n != 1);
    nb,    Norwegian Bokmal,      nplurals=2; plural=(n != 1);
    ne,    Nepali,                nplurals=2; plural=(n != 1);
    nl,    Dutch,                 nplurals=2; plural=(n != 1);
    nn,    Norwegian Nynorsk,     nplurals=2; plural=(n != 1);
    no,    Norwegian (old code),  nplurals=2; plural=(n != 1);
    nso,   Northern Sotho,        nplurals=2; plural=(n != 1);
    oc,    Occitan,               nplurals=2; plural=(n > 1);
    or,    Oriya,                 nplurals=2; plural=(n != 1);
    pa,    Punjabi,               nplurals=2; plural=(n != 1);
    pap,   Papiamento,            nplurals=2; plural=(n != 1);
    pl,    Polish,                nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);
    pms,   Piemontese,            nplurals=2; plural=(n != 1);
    ps,    Pashto,                nplurals=2; plural=(n != 1);
    pt,    Portuguese,            nplurals=2; plural=(n != 1);
    pt_BR, Brazilian Portuguese,  nplurals=2; plural=(n > 1);
    rm,    Romansh,               nplurals=2; plural=(n != 1);
    ro,    Romanian,              nplurals=3; plural=(n==1 ? 0 : (n==0 || (n%100 > 0 && n%100 < 20)) ? 1 : 2);
    ru,    Russian,               nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);
    rw,    Kinyarwanda,           nplurals=2; plural=(n != 1);
    sah,   Yakut,                 nplurals=1; plural=0;
    sat,   Santali,               nplurals=2; plural=(n != 1);
    sco,   Scots,                 nplurals=2; plural=(n != 1);
    sd,    Sindhi,                nplurals=2; plural=(n != 1);
    se,    Northern Sami,         nplurals=2; plural=(n != 1);
    si,    Sinhala,               nplurals=2; plural=(n != 1);
    sk,    Slovak,                nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;
    sl,    Slovenian,             nplurals=4; plural=(n%100==1 ? 1 : n%100==2 ? 2 : n%100==3 || n%100==4 ? 3 : 0);
    so,    Somali,                nplurals=2; plural=(n != 1);
    son,   Songhay,               nplurals=2; plural=(n != 1);
    sq,    Albanian,              nplurals=2; plural=(n != 1);
    sr,    Serbian,               nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);
    su,    Sundanese,             nplurals=1; plural=0;
    sv,    Swedish,               nplurals=2; plural=(n != 1);
    sw,    Swahili,               nplurals=2; plural=(n != 1);
    ta,    Tamil,                 nplurals=2; plural=(n != 1);
    te,    Telugu,                nplurals=2; plural=(n != 1);
    tg,    Tajik,                 nplurals=2; plural=(n > 1);
    th,    Thai,                  nplurals=1; plural=0;
    ti,    Tigrinya,              nplurals=2; plural=(n > 1);
    tk,    Turkmen,               nplurals=2; plural=(n != 1);
    tr,    Turkish,               nplurals=2; plural=(n > 1);
    tt,    Tatar,                 nplurals=1; plural=0;
    ug,    Uyghur,                nplurals=1; plural=0;
    uk,    Ukrainian,             nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);
    ur,    Urdu,                  nplurals=2; plural=(n != 1);
    uz,    Uzbek,                 nplurals=2; plural=(n > 1);
    vi,    Vietnamese,            nplurals=1; plural=0;
    wa,    Walloon,               nplurals=2; plural=(n > 1);
    wo,    Wolof,                 nplurals=1; plural=0;
    yo,    Yoruba,                nplurals=2; plural=(n != 1);
    zh,    Chinese,               nplurals=1; plural=0;
    zh_p,  Chinese pronoun,       nplurals=2; plural=(n > 1);
    """
    |> String.split("\n", trim: true)
    |> Enum.map(&String.split(&1, ",", parts: 3, trim: true))
    |> Map.new(fn [iso_code, _name, plural_form] ->
      {:ok, %Expo.PluralForms{} = plural_forms} =
        plural_form |> String.trim() |> Expo.PluralForms.parse()

      {String.trim(iso_code), plural_forms}
    end)

  @spec known_locales() :: [String.t(), ...]
  def known_locales, do: unquote(Map.keys(known_plural_forms))

  @spec plural_form(String.t()) :: {:ok, Expo.PluralForms.t()} | :error
  def plural_form(iso_language_tag)

  for {iso_language_tag, plural_form} <- known_plural_forms do
    def plural_form(unquote(iso_language_tag)), do: {:ok, unquote(Macro.escape(plural_form))}
  end

  def plural_form(locale) do
    case String.split(locale, "_", parts: 2, trim: true) do
      [lang, _territory] -> plural_form(lang)
      _other -> :error
    end
  end
end
