defmodule Wasomi.CatalogTest do
  use Wasomi.DataCase

  alias Wasomi.Catalog

  describe "courses" do
    alias Wasomi.Catalog.Course

    import Wasomi.CatalogFixtures

    @invalid_attrs %{
      position: nil,
      status: nil,
      description: nil,
      title: nil,
      currency: nil,
      slug: nil,
      subtitle: nil,
      thumbnail_key: nil,
      price_minor: nil
    }

    test "list_courses/0 returns all courses" do
      course = course_fixture()
      assert Catalog.list_courses() == [course]
    end

    test "get_course!/1 returns the course with given id" do
      course = course_fixture()
      assert Catalog.get_course!(course.id) == course
    end

    test "create_course/1 with valid data creates a course" do
      valid_attrs = %{
        position: 42,
        status: :draft,
        description: "some description",
        title: "some title",
        currency: "kes",
        slug: "Some Course",
        subtitle: "some subtitle",
        thumbnail_key: "some thumbnail_key",
        price_minor: 42
      }

      assert {:ok, %Course{} = course} = Catalog.create_course(valid_attrs)
      assert course.position == 42
      assert course.status == :draft
      assert course.description == "some description"
      assert course.title == "some title"
      assert course.currency == "KES"
      assert course.slug == "some-course"
      assert course.subtitle == "some subtitle"
      assert course.thumbnail_key == "some thumbnail_key"
      assert course.price_minor == 42
    end

    test "create_course/1 auto-assigns the next position when none is given" do
      _c1 = course_fixture(position: 5, slug: "first-course")

      assert {:ok, %Course{position: 6}} =
               Catalog.create_course(%{
                 title: "Second Course",
                 description: "desc",
                 subtitle: "sub",
                 thumbnail_key: "key",
                 price_minor: 100
               })
    end

    test "create_course/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_course(@invalid_attrs)
    end

    test "update_course/2 with valid data updates the course" do
      course = course_fixture(status: :draft)

      update_attrs = %{
        position: 43,
        status: :in_review,
        description: "some updated description",
        title: "some updated title",
        currency: "usd",
        slug: "Some Updated Slug",
        subtitle: "some updated subtitle",
        thumbnail_key: "some updated thumbnail_key",
        price_minor: 43
      }

      assert {:ok, %Course{} = course} = Catalog.update_course(course, update_attrs)
      assert course.position == 43
      assert course.status == :in_review
      assert course.description == "some updated description"
      assert course.title == "some updated title"
      assert course.currency == "USD"
      assert course.slug == "some-updated-slug"
      assert course.subtitle == "some updated subtitle"
      assert course.thumbnail_key == "some updated thumbnail_key"
      assert course.price_minor == 43
    end

    test "update_course/2 silently ignores an attempt to set status: :published directly" do
      course = course_fixture(status: :draft)

      assert {:ok, %Course{} = updated} =
               Catalog.update_course(course, %{status: :published, title: "Still draft"})

      assert updated.status == :draft
      assert updated.title == "Still draft"
    end

    test "update_course/2 with invalid data returns error changeset" do
      course = course_fixture()
      assert {:error, %Ecto.Changeset{}} = Catalog.update_course(course, @invalid_attrs)
      assert course == Catalog.get_course!(course.id)
    end

    test "delete_course/1 deletes the course" do
      course = course_fixture()
      assert {:ok, %Course{}} = Catalog.delete_course(course)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_course!(course.id) end
    end

    test "change_course/1 returns a course changeset" do
      course = course_fixture()
      assert %Ecto.Changeset{} = Catalog.change_course(course)
    end

    test "list_published_courses/0 only returns published courses in position order" do
      _draft = course_fixture(position: 1, status: :draft)
      second = course_fixture(position: 2, status: :published)
      first = course_fixture(position: 1, status: :published)

      assert Enum.map(Catalog.list_published_courses(), & &1.id) == [first.id, second.id]
    end

    test "pricing helpers preserve integer minor units and currency" do
      course = course_fixture(price_minor: 15_000_00, currency: "KES")

      assert %Money{amount: 15_000_00, currency: :KES} = Catalog.price(course)
      assert Catalog.format_price(course) =~ "KES"
    end
  end

  describe "modules" do
    alias Wasomi.Catalog.CourseModule

    import Wasomi.CatalogFixtures

    @invalid_attrs %{position: nil, description: nil, title: nil}

    test "list_modules/0 returns all modules" do
      course_module = course_module_fixture()
      assert Catalog.list_modules() == [course_module]
    end

    test "get_course_module!/1 returns the course_module with given id" do
      course_module = course_module_fixture()
      assert Catalog.get_course_module!(course_module.id) == course_module
    end

    test "create_course_module/1 with valid data creates a course_module" do
      course = course_fixture()

      valid_attrs = %{
        course_id: course.id,
        position: 42,
        description: "some description",
        title: "some title"
      }

      assert {:ok, %CourseModule{} = course_module} = Catalog.create_course_module(valid_attrs)
      assert course_module.position == 42
      assert course_module.description == "some description"
      assert course_module.title == "some title"
    end

    test "create_course_module/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_course_module(@invalid_attrs)
    end

    test "update_course_module/2 with valid data updates the course_module" do
      course_module = course_module_fixture()

      update_attrs = %{
        position: 43,
        description: "some updated description",
        title: "some updated title"
      }

      assert {:ok, %CourseModule{} = course_module} =
               Catalog.update_course_module(course_module, update_attrs)

      assert course_module.position == 43
      assert course_module.description == "some updated description"
      assert course_module.title == "some updated title"
    end

    test "update_course_module/2 with invalid data returns error changeset" do
      course_module = course_module_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Catalog.update_course_module(course_module, @invalid_attrs)

      assert course_module == Catalog.get_course_module!(course_module.id)
    end

    test "delete_course_module/1 deletes the course_module" do
      course_module = course_module_fixture()
      assert {:ok, %CourseModule{}} = Catalog.delete_course_module(course_module)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_course_module!(course_module.id) end
    end

    test "change_course_module/1 returns a course_module changeset" do
      course_module = course_module_fixture()
      assert %Ecto.Changeset{} = Catalog.change_course_module(course_module)
    end

    test "reorder_course_modules/2 persists modules in the requested order" do
      course = course_fixture()
      first = course_module_fixture(course_id: course.id, position: 1, title: "First")
      second = course_module_fixture(course_id: course.id, position: 2, title: "Second")
      third = course_module_fixture(course_id: course.id, position: 3, title: "Third")

      assert {:ok, _} = Catalog.reorder_course_modules(course.id, [third.id, first.id, second.id])

      course = Catalog.get_course_with_outline!(course.id)
      assert Enum.map(course.modules, & &1.id) == [third.id, first.id, second.id]
      assert Enum.map(course.modules, & &1.position) == [1, 2, 3]
    end
  end

  describe "lectures" do
    alias Wasomi.Catalog.Lecture

    import Wasomi.CatalogFixtures

    @invalid_attrs %{
      position: nil,
      description: nil,
      title: nil,
      video_provider: nil,
      video_asset_id: nil,
      duration_seconds: nil
    }

    test "list_lectures/0 returns all lectures" do
      lecture = lecture_fixture()
      assert Catalog.list_lectures() == [lecture]
    end

    test "get_lecture!/1 returns the lecture with given id" do
      lecture = lecture_fixture()
      assert Catalog.get_lecture!(lecture.id) == lecture
    end

    test "create_lecture/1 with valid data creates a lecture" do
      course_module = course_module_fixture()

      valid_attrs = %{
        module_id: course_module.id,
        position: 42,
        description: "some description",
        title: "some title",
        video_provider: :mux,
        video_asset_id: "some video_asset_id",
        duration_seconds: 42
      }

      assert {:ok, %Lecture{} = lecture} = Catalog.create_lecture(valid_attrs)
      assert lecture.position == 42
      assert lecture.description == "some description"
      assert lecture.title == "some title"
      assert lecture.video_provider == :mux
      assert lecture.video_asset_id == "some video_asset_id"
      assert lecture.duration_seconds == 42
    end

    test "create_lecture/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_lecture(@invalid_attrs)
    end

    test "update_lecture/2 with valid data updates the lecture" do
      lecture = lecture_fixture()

      update_attrs = %{
        position: 43,
        description: "some updated description",
        title: "some updated title",
        video_provider: :cloudflare,
        video_asset_id: "some updated video_asset_id",
        duration_seconds: 43
      }

      assert {:ok, %Lecture{} = lecture} = Catalog.update_lecture(lecture, update_attrs)
      assert lecture.position == 43
      assert lecture.description == "some updated description"
      assert lecture.title == "some updated title"
      assert lecture.video_provider == :cloudflare
      assert lecture.video_asset_id == "some updated video_asset_id"
      assert lecture.duration_seconds == 43
    end

    test "update_lecture/2 with invalid data returns error changeset" do
      lecture = lecture_fixture()
      assert {:error, %Ecto.Changeset{}} = Catalog.update_lecture(lecture, @invalid_attrs)
      assert lecture == Catalog.get_lecture!(lecture.id)
    end

    test "delete_lecture/1 deletes the lecture" do
      lecture = lecture_fixture()
      assert {:ok, %Lecture{}} = Catalog.delete_lecture(lecture)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_lecture!(lecture.id) end
    end

    test "change_lecture/1 returns a lecture changeset" do
      lecture = lecture_fixture()
      assert %Ecto.Changeset{} = Catalog.change_lecture(lecture)
    end

    test "reorder_module_lectures/2 persists lectures in the requested order" do
      course_module = course_module_fixture()
      first = lecture_fixture(module_id: course_module.id, position: 1, title: "First")
      second = lecture_fixture(module_id: course_module.id, position: 2, title: "Second")
      third = lecture_fixture(module_id: course_module.id, position: 3, title: "Third")

      assert {:ok, _} =
               Catalog.reorder_module_lectures(course_module.id, [second.id, third.id, first.id])

      course = Catalog.get_course_with_outline!(course_module.course_id)
      [module] = course.modules
      assert Enum.map(module.lectures, & &1.id) == [second.id, third.id, first.id]
      assert Enum.map(module.lectures, & &1.position) == [1, 2, 3]
    end

    test "replaces lecture resources and questions atomically" do
      lecture = lecture_fixture()
      old_resource = lecture_resource_fixture(lecture_id: lecture.id)
      old_question = lecture_question_fixture(lecture_id: lecture.id)

      assert {:ok, updated} =
               Catalog.update_lecture_content(
                 lecture,
                 %{title: "Updated lecture"},
                 [%{kind: :link, name: "Further reading", url: "https://example.com/reading"}],
                 [%{question: "Why?", answer: "Because."}]
               )

      refute Wasomi.Repo.get(Wasomi.Catalog.LectureResource, old_resource.id)
      refute Wasomi.Repo.get(Wasomi.Catalog.LectureQuestion, old_question.id)
      assert [%{kind: :link, position: 1, url: "https://example.com/reading"}] = updated.resources
      assert [%{question: "Why?", position: 1}] = updated.questions
    end

    test "returns a changeset and rolls back invalid lecture content" do
      lecture = lecture_fixture()
      resource = lecture_resource_fixture(lecture_id: lecture.id)

      assert {:error, %Ecto.Changeset{}} =
               Catalog.update_lecture_content(
                 lecture,
                 %{title: "Updated lecture"},
                 [%{kind: :document, name: "Missing storage key"}],
                 []
               )

      assert Catalog.get_lecture!(lecture.id).title == lecture.title
      assert Wasomi.Repo.get!(Wasomi.Catalog.LectureResource, resource.id).id == resource.id
    end

    test "course outlines preload ordered resources and questions" do
      course = course_fixture()
      course_module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: course_module.id, position: 1)

      later_resource =
        lecture_resource_fixture(lecture_id: lecture.id, position: 2, name: "Later")

      first_resource =
        lecture_resource_fixture(lecture_id: lecture.id, position: 1, name: "First")

      later_question = lecture_question_fixture(lecture_id: lecture.id, position: 2)
      first_question = lecture_question_fixture(lecture_id: lecture.id, position: 1)

      loaded = Catalog.get_course_with_outline!(course.id)
      loaded_lecture = loaded.modules |> hd() |> Map.fetch!(:lectures) |> hd()
      assert Enum.map(loaded_lecture.resources, & &1.id) == [first_resource.id, later_resource.id]
      assert Enum.map(loaded_lecture.questions, & &1.id) == [first_question.id, later_question.id]
    end

    test "slug lookup preloads modules and lectures in position order" do
      course = course_fixture(status: :published)
      later_module = course_module_fixture(course_id: course.id, position: 2)
      first_module = course_module_fixture(course_id: course.id, position: 1)
      later_lecture = lecture_fixture(module_id: first_module.id, position: 2)
      first_lecture = lecture_fixture(module_id: first_module.id, position: 1)

      loaded = Catalog.get_published_course_by_slug!(course.slug)

      assert Enum.map(loaded.modules, & &1.id) == [first_module.id, later_module.id]

      assert Enum.map(hd(loaded.modules).lectures, & &1.id) == [
               first_lecture.id,
               later_lecture.id
             ]
    end
  end

  describe "publish lifecycle" do
    import Wasomi.CatalogFixtures

    alias Wasomi.Catalog.PublishGuard

    test "submit_course_for_review/1 moves a draft course to in_review" do
      course = course_fixture(status: :draft)

      assert {:ok, updated} = Catalog.submit_course_for_review(course)
      assert updated.status == :in_review
    end

    test "PublishGuard.check/1 lists every missing requirement for a bare course" do
      # price_minor is required (and NOT NULL) at both the changeset and DB
      # level, so a real persisted course can never actually have a nil
      # price — build the struct directly to unit-test that branch in
      # isolation (same defense-in-depth reasoning as the video check).
      course = %Wasomi.Catalog.Course{modules: [], price_minor: nil, thumbnail_key: ""}

      assert {:error, issues} = PublishGuard.check(course)
      assert "Add at least one module." in issues
      assert "Set a course price." in issues
      assert "Attach a course thumbnail." in issues
      refute "Add at least one lecture." in issues
    end

    test "PublishGuard.check/1 treats a free (zero-price) course as having its price set" do
      course = course_fixture(price_minor: 0, thumbnail_key: "cover.jpg")
      course_module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: course_module.id, position: 1, video_asset_id: "abc123")

      assert PublishGuard.check(Catalog.get_course_with_outline!(course.id)) == :ok
    end

    test "PublishGuard.check/1 flags a module with no lectures" do
      course = course_fixture()
      course_module_fixture(course_id: course.id, position: 1)

      assert {:error, issues} =
               Catalog.get_course_with_outline!(course.id) |> PublishGuard.check()

      assert "Add at least one lecture." in issues
    end

    test "PublishGuard.check/1 flags a lecture with no video attached" do
      # `Wasomi.Catalog.Lecture`'s own changeset already requires
      # `video_asset_id`, so a real persisted lecture can never actually
      # reach the guard in this state today — build the struct directly to
      # unit-test the guard's own logic in isolation (defense in depth: if
      # that requirement is ever relaxed for a "video pending upload" draft
      # lecture, this check is already correctly in place).
      course = %Wasomi.Catalog.Course{
        modules: [
          %Wasomi.Catalog.CourseModule{
            lectures: [%Wasomi.Catalog.Lecture{video_asset_id: nil}]
          }
        ]
      }

      assert {:error, issues} = PublishGuard.check(course)
      assert "Every lecture needs a video attached." in issues
    end

    test "PublishGuard.check/1 passes a fully-prepared course" do
      course = course_fixture(price_minor: 150_000, thumbnail_key: "cover.jpg")
      course_module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: course_module.id, position: 1, video_asset_id: "abc123")

      assert PublishGuard.check(Catalog.get_course_with_outline!(course.id)) == :ok
    end

    test "publish_course/1 publishes a ready course and it appears in the public catalog" do
      course =
        course_fixture(status: :in_review, price_minor: 150_000, thumbnail_key: "cover.jpg")

      course_module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: course_module.id, position: 1, video_asset_id: "abc123")

      assert {:ok, published} = Catalog.publish_course(course)
      assert published.status == :published
      assert Enum.any?(Catalog.list_published_courses(), &(&1.id == course.id))
    end

    test "publish_course/1 leaves the status unchanged and returns the checklist on failure" do
      course = course_fixture(status: :draft, price_minor: 0)

      assert {:error, issues} = Catalog.publish_course(course)
      assert is_list(issues)
      assert Catalog.get_course!(course.id).status == :draft
    end

    test "publish_course/1 succeeds directly from :draft — :in_review is not a required step" do
      course =
        course_fixture(status: :draft, price_minor: 150_000, thumbnail_key: "cover.jpg")

      course_module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: course_module.id, position: 1, video_asset_id: "abc123")

      assert {:ok, published} = Catalog.publish_course(course)
      assert published.status == :published
    end
  end

  describe "certificate configuration" do
    import Wasomi.CatalogFixtures

    test "change_course_certificate/2 does not require issuer/signatory fields when disabled" do
      course = course_fixture()

      changeset = Catalog.change_course_certificate(course, %{"certificate_enabled" => "false"})

      assert changeset.valid?
    end

    test "change_course_certificate/2 requires issuer/signatory fields when enabled" do
      course = course_fixture()

      changeset = Catalog.change_course_certificate(course, %{"certificate_enabled" => "true"})

      refute changeset.valid?

      assert %{
               certificate_issuer_name: ["can't be blank"],
               certificate_signatory_name: ["can't be blank"],
               certificate_signatory_title: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "update_course_certificate/2 persists a full certificate configuration" do
      # A locally configured R2_PUBLIC_URL (via .env) would otherwise make
      # this test's signature host-trust check depend on the developer's
      # machine instead of being deterministic.
      previous = Application.get_env(:wasomi, :r2_public_url)
      on_exit(fn -> Application.put_env(:wasomi, :r2_public_url, previous) end)
      Application.put_env(:wasomi, :r2_public_url, "https://example.com")

      course = course_fixture()

      assert {:ok, updated} =
               Catalog.update_course_certificate(course, %{
                 "certificate_enabled" => "true",
                 "certificate_issuer_name" => "GS1 Kenya",
                 "certificate_signatory_name" => "Jane Doe",
                 "certificate_signatory_title" => "Country Manager",
                 "certificate_signature_key" => "https://example.com/signature.png"
               })

      assert updated.certificate_enabled
      assert updated.certificate_issuer_name == "GS1 Kenya"
      assert updated.certificate_signatory_name == "Jane Doe"
      assert updated.certificate_signatory_title == "Country Manager"
      assert updated.certificate_signature_key == "https://example.com/signature.png"
    end

    test "change_course_certificate/2 rejects a signature URL pointing at an untrusted host when R2 is configured" do
      previous = Application.get_env(:wasomi, :r2_public_url)
      on_exit(fn -> Application.put_env(:wasomi, :r2_public_url, previous) end)
      Application.put_env(:wasomi, :r2_public_url, "https://cdn.example.test")

      course = course_fixture()

      changeset =
        Catalog.change_course_certificate(course, %{
          "certificate_signature_key" => "http://169.254.169.254/latest/meta-data/"
        })

      refute changeset.valid?
      assert %{certificate_signature_key: ["must be a valid http(s) URL"]} = errors_on(changeset)

      trusted_changeset =
        Catalog.change_course_certificate(course, %{
          "certificate_signature_key" => "https://cdn.example.test/certificates/1/sig.png"
        })

      refute Keyword.has_key?(trusted_changeset.errors, :certificate_signature_key)
    end

    test "change_course_certificate/2 rejects every signature URL — even a plausible one — when R2 isn't configured" do
      previous = Application.get_env(:wasomi, :r2_public_url)
      on_exit(fn -> Application.put_env(:wasomi, :r2_public_url, previous) end)
      Application.delete_env(:wasomi, :r2_public_url)

      course = course_fixture()

      changeset =
        Catalog.change_course_certificate(course, %{
          "certificate_signature_key" => "https://cdn.example.test/certificates/1/sig.png"
        })

      refute changeset.valid?
      assert %{certificate_signature_key: ["must be a valid http(s) URL"]} = errors_on(changeset)
    end

    test "change_course_certificate/2 rejects a non-http(s) signature URL" do
      course = course_fixture()

      changeset =
        Catalog.change_course_certificate(course, %{
          "certificate_signature_key" => "javascript:alert(1)"
        })

      refute changeset.valid?
      assert %{certificate_signature_key: ["must be a valid http(s) URL"]} = errors_on(changeset)
    end

    test "change_course_certificate/2 treats a blank signature URL as absent, not invalid" do
      course = course_fixture()

      changeset =
        Catalog.change_course_certificate(course, %{
          "certificate_enabled" => "false",
          "certificate_signature_key" => ""
        })

      assert changeset.valid?
    end
  end
end
