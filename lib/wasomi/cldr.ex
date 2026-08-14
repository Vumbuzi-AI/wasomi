defmodule Wasomi.Cldr do
  use Cldr,
    locales: ["en", "en-KE"],
    default_locale: "en",
    providers: [Cldr.Number]
end
