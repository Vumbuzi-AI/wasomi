defmodule Wasomi.Assessments.LectureResourceReader.StorageTest do
  use Wasomi.DataCase, async: true

  import Mox
  import Wasomi.CatalogFixtures

  alias Wasomi.Assessments.LectureResourceReader.Storage

  setup :verify_on_exit!

  test "extracts text from a docx document resource" do
    resource =
      lecture_resource_fixture(
        kind: :document,
        name: "document.docx",
        storage_key: "lectures/plan.docx"
      )

    expect(Wasomi.DocxExtractorMock, :extract_text, fn binary ->
      assert String.starts_with?(binary, "PK")
      {:ok, "Extracted DOCX prose."}
    end)

    files = [
      {~c"word/document.xml",
       "<w:p><w:t>Extracted DOCX prose.</w:t></w:p>"}
    ]

    {:ok, {~c"mem", docx_binary}} = :zip.create(~c"mem", files, [:memory])

    Req.Test.stub(Storage, fn conn ->
      Req.Test.html(conn, docx_binary)
    end)

    assert {:ok, "Extracted DOCX prose."} = Storage.extract_text(resource)
  end

  test "rejects non-document resources" do
    video_res = lecture_resource_fixture(kind: :video, storage_key: "vid.mp4")
    assert {:error, {:unsupported_resource_kind, :video}} = Storage.extract_text(video_res)
  end
end
