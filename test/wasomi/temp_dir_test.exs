defmodule Wasomi.TempDirTest do
  use ExUnit.Case, async: true

  alias Wasomi.TempDir

  test "runs fun with a fresh, writable directory and removes it afterward" do
    dir =
      TempDir.with_tmp_dir(fn dir ->
        assert File.dir?(dir)
        File.write!(Path.join(dir, "scratch.txt"), "hello")
        dir
      end)

    refute File.exists?(dir)
  end

  test "removes the directory even if fun raises" do
    assert_raise RuntimeError, "boom", fn ->
      TempDir.with_tmp_dir(fn dir ->
        send(self(), {:dir, dir})
        raise "boom"
      end)
    end

    assert_receive {:dir, dir}
    refute File.exists?(dir)
  end

  test "two concurrent calls get distinct directories" do
    dir1 = TempDir.with_tmp_dir(& &1)
    dir2 = TempDir.with_tmp_dir(& &1)

    refute dir1 == dir2
  end
end
