defmodule Wasomi.Assessments.StudyGuidesTest do
  use Wasomi.DataCase, async: true

  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures

  alias Wasomi.Assessments

  describe "create_study_guide/3" do
    test "creates a pending guide scoped to a lecture" do
      user = user_fixture()
      module = course_module_fixture()
      lecture = lecture_fixture(module_id: module.id, position: 1)

      assert {:ok, guide} =
               Assessments.create_study_guide(user, lecture, %{
                 style: :story,
                 depth: :deep,
                 reading_level: :beginner,
                 include_examples: true,
                 include_key_terms: false,
                 focus: "  check digits  "
               })

      assert guide.status == :pending
      assert guide.user_id == user.id
      assert guide.lecture_id == lecture.id
      refute guide.module_id
      assert guide.style == :story
      # Trimmed on the way in, so the prompt never carries the form's padding.
      assert guide.focus == "check digits"
    end

    test "an all-whitespace focus is stored as no focus at all" do
      assert {:ok, guide} =
               Assessments.create_study_guide(user_fixture(), course_module_fixture(), %{
                 style: :notes,
                 depth: :brief,
                 reading_level: :intermediate,
                 focus: "   "
               })

      refute guide.focus
    end

    test "rejects a style the UI doesn't offer" do
      assert {:error, changeset} =
               Assessments.create_study_guide(user_fixture(), course_module_fixture(), %{
                 style: :limerick,
                 depth: :brief,
                 reading_level: :intermediate
               })

      assert errors_on(changeset).style != []
    end

    test "two guides in different styles coexist for the same learner and scope" do
      user = user_fixture()
      module = course_module_fixture()

      notes = study_guide_fixture(user: user, module: module, style: :notes)
      story = study_guide_fixture(user: user, module: module, style: :story)

      assert [latest, older] = Assessments.list_study_guides(user, module)
      assert latest.id == story.id
      assert older.id == notes.id
    end

    test "one learner's guides are invisible to another" do
      module = course_module_fixture()
      mine = study_guide_fixture(module: module)
      other = user_fixture()

      assert Assessments.list_study_guides(other, module) == []
      refute Assessments.get_user_study_guide(other, mine.id)
    end
  end

  describe "mark_study_guide_ready/2" do
    test "writes the document, numbers its sections, and reports how many landed" do
      guide = study_guide_fixture()

      assert {:ok, 2} = Assessments.mark_study_guide_ready(guide, draft_study_guide_attrs())

      ready =
        guide.id |> Assessments.get_study_guide!() |> Assessments.load_study_guide_sections()

      assert ready.status == :ready
      assert ready.generated_at
      assert ready.sections_generated_count == 2
      assert ready.summary =~ "company prefix"
      assert Enum.map(ready.study_guide_sections, & &1.position) == [1, 2]
      assert [%{term: "GTIN", definition: definition}] = ready.key_terms
      assert definition =~ "trade item"
    end

    test "skips a malformed section rather than failing the whole document" do
      guide = study_guide_fixture()

      draft =
        draft_study_guide_attrs(
          sections: [
            %{heading: nil, body: "Orphan prose", bullets: [], callout: nil},
            %{heading: "Real section", body: "Real prose", bullets: [], callout: nil}
          ]
        )

      assert {:ok, 1} = Assessments.mark_study_guide_ready(guide, draft)

      ready =
        guide.id |> Assessments.get_study_guide!() |> Assessments.load_study_guide_sections()

      assert ready.status == :ready
      assert [%{heading: "Real section", position: 1}] = ready.study_guide_sections
    end

    test "a document with no usable section is an error, and the guide stays unready" do
      guide = study_guide_fixture()

      assert {:error, :no_valid_sections_generated} =
               Assessments.mark_study_guide_ready(guide, draft_study_guide_attrs(sections: []))

      assert Assessments.get_study_guide!(guide.id).status == :pending
    end

    test "broadcasts to a subscriber so an open panel swaps in the finished guide" do
      guide = study_guide_fixture()
      Assessments.subscribe_to_study_guide(guide)

      Assessments.mark_study_guide_processing(guide)
      assert_receive {:study_guide_updated, %{status: :processing}}

      Assessments.mark_study_guide_ready(guide, draft_study_guide_attrs())
      assert_receive {:study_guide_updated, %{status: :ready}}
    end

    test "unsubscribing stops later updates arriving" do
      guide = study_guide_fixture()
      Assessments.subscribe_to_study_guide(guide)
      Assessments.unsubscribe_from_study_guide(guide)

      Assessments.mark_study_guide_failed(guide, "boom")

      refute_receive {:study_guide_updated, _guide}
    end
  end

  describe "latest_study_guide/2 and delete_user_study_guide/2" do
    test "the latest guide comes back with its sections loaded" do
      user = user_fixture()
      module = course_module_fixture()
      study_guide_fixture(user: user, module: module)
      ready = ready_study_guide_fixture(user: user, module: module)

      latest = Assessments.latest_study_guide(user, module)
      assert latest.id == ready.id
      assert length(latest.study_guide_sections) == 2
    end

    test "nothing generated yet is nil rather than an empty guide" do
      refute Assessments.latest_study_guide(user_fixture(), course_module_fixture())
    end

    test "a learner can delete their own guide, and only their own" do
      user = user_fixture()
      guide = study_guide_fixture(user: user)

      assert {:error, :not_found} = Assessments.delete_user_study_guide(user_fixture(), guide.id)
      assert {:ok, _deleted} = Assessments.delete_user_study_guide(user, guide.id)
      refute Assessments.get_user_study_guide(user, guide.id)
    end
  end
end
