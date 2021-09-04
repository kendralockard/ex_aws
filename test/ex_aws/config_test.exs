defmodule ExAws.ConfigTest do
  use ExUnit.Case, async: false

  import Mox

  setup do
    Application.delete_env(:ex_aws, :awscli_credentials)

    on_exit(fn ->
      Application.delete_env(:ex_aws, :awscli_credentials)
    end)
  end

  setup :set_mox_global
  setup :verify_on_exit!

  test "overrides work properly" do
    config = ExAws.Config.new(:s3, region: "us-west-2")
    assert config.region == "us-west-2"
  end

  test "{:system} style configs work" do
    value = "foo"
    System.put_env("ExAwsConfigTest", value)

    assert :s3
           |> ExAws.Config.new(
             access_key_id: {:system, "ExAwsConfigTest"},
             secret_access_key: {:system, "AWS_SECURITY_TOKEN"}
           )
           |> Map.get(:access_key_id) == value
  end

  test "security_token is configured properly" do
    value = "security_token"
    System.put_env("AWS_SECURITY_TOKEN", value)

    assert :s3
           |> ExAws.Config.new(
             access_key_id: {:system, "AWS_SECURITY_TOKEN"},
             security_token: {:system, "AWS_SECURITY_TOKEN"}
           )
           |> Map.get(:security_token) == value
  end

  test "config file is parsed if no given credentials in configuraion" do
    profile = "default"

    Mox.expect(ExAws.Credentials.InitMock, :security_credentials, 1, fn ^profile ->
      %{region: "eu-west-1"}
    end)

    config = ExAws.Config.awscli_auth_credentials(profile, ExAws.Credentials.InitMock)

    assert config.region == "eu-west-1"
  end

  test "profile config returned if given credentials in configuration" do
    profile = "default"

    example_credentials = %{
      "default" => %{
        region: "eu-west-1"
      }
    }

    Application.put_env(:ex_aws, :awscli_credentials, example_credentials)

    Mox.expect(ExAws.Credentials.InitMock, :security_credentials, 0, fn ^profile ->
      %{region: "eu-west-1"}
    end)

    config = ExAws.Config.awscli_auth_credentials(profile, ExAws.Credentials.InitMock)

    assert config.region == "eu-west-1"
  end

  test "error on wrong credentials configuration" do
    profile = "other"

    example_credentials = %{
      "default" => %{
        region: "eu-west-1"
      }
    }

    Application.put_env(:ex_aws, :awscli_credentials, example_credentials)

    Mox.expect(ExAws.Credentials.InitMock, :security_credentials, 0, fn ^profile ->
      %{region: "eu-west-1"}
    end)

    assert_raise RuntimeError, fn ->
      ExAws.Config.awscli_auth_credentials(profile, ExAws.Credentials.InitMock)
    end
  end

  test "region as a plain string" do
    region_value = "us-west-1"

    assert :s3
           |> ExAws.Config.new(region: region_value)
           |> Map.get(:region) == region_value
  end

  test "region as an envar" do
    region_value = "us-west-1"
    System.put_env("AWS_REGION", region_value)

    assert :s3
           |> ExAws.Config.new(region: {:system, "AWS_REGION"})
           |> Map.get(:region) == region_value
  end

  describe "cli config merging tests" do
    setup do
      :ok = ExAws.Config.AuthCache.reset()
      orig_env = Application.get_all_env(:ex_aws)

      on_exit(fn ->
        Enum.map(orig_env, fn {k, v} -> Application.put_env(:ex_aws, k, v) end)
      end)
    end

    test "runtime config is correctly constructed" do
      Enum.map(
        [
          access_key_id: {:awscli, "default", 30},
          secret_access_key: {:awscli, "default", 30},
          region: "us-east-1",
          credentials_ini_provider: ExAws.Credentials.InitMock
        ],
        fn {k, v} -> Application.put_env(:ex_aws, k, v) end
      )

      Mox.expect(ExAws.Credentials.InitMock, :security_credentials, 1, fn "default" ->
        %{
          region: "eu-west-1",
          access_key_id: "key_id",
          secret_access_key: "secret_key"
        }
      end)

      config = ExAws.Config.new(:sqs)

      assert config.region == "us-east-1"
      assert config.access_key_id == "key_id"
      assert config.secret_access_key == "secret_key"
    end

    test "runtime config should not overwrite explicit config" do
      System.put_env("EX_AWS_TEST_ID", "system_id")
      System.put_env("EX_AWS_TEST_KEY", "system_key")
      System.put_env("EX_AWS_TEST_REGION", "us-east-2")

      Enum.map(
        [
          access_key_id: [{:awscli, "default", 30}, {:system, "EX_AWS_TEST_ID"}],
          secret_access_key: [{:awscli, "default", 30}, {:system, "EX_AWS_TEST_KEY"}],
          region: [{:awscli, "default", 30}, {:system, "EX_AWS_TEST_REGION"}],
          credentials_ini_provider: ExAws.Credentials.InitMock
        ],
        fn {k, v} -> Application.put_env(:ex_aws, k, v) end
      )

      Mox.expect(ExAws.Credentials.InitMock, :security_credentials, 1, fn "default" ->
        %{region: "eu-west-1"}
      end)

      config = ExAws.Config.new(:sqs)

      assert config.region == "eu-west-1"
      assert config.access_key_id == "system_id"
      assert config.secret_access_key == "system_key"
    end
  end
end
