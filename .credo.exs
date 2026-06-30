%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/",
          "config/",
          "priv/repo/seeds.exs"
        ],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: [
        {Credo.Check.Consistency.ExceptionNames},
        {Credo.Check.Consistency.LineEndings},
        {Credo.Check.Consistency.ParameterPatternMatching},
        {Credo.Check.Consistency.SpaceAroundOperators},
        {Credo.Check.Consistency.SpaceInParentheses},
        {Credo.Check.Consistency.TabsOrSpaces},
        {Credo.Check.Design.TagTODO, exit_status: 0},
        {Credo.Check.Design.TagFIXME},
        {Credo.Check.Readability.LargeNumbers, false},
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        {Credo.Check.Refactor.Nesting, false},
        {Credo.Check.Warning.BoolOperationOnSameValues},
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck},
        {Credo.Check.Warning.IExPry},
        {Credo.Check.Warning.IoInspect},
        {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig},
        {Credo.Check.Warning.OperationOnSameValues},
        {Credo.Check.Warning.OperationWithConstantResult},
        {Credo.Check.Warning.RaiseInsideRescue},
        {Credo.Check.Warning.SpecWithStruct},
        {Credo.Check.Warning.UnsafeExec}
      ]
    }
  ]
}
