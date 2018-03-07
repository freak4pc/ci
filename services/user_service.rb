require_relative "data_sources/json_user_data_source"
require_relative "../shared/models/github_provider_credential"
require_relative "../shared/logging_module"

module FastlaneCI
  # Provides access to user stuff
  class UserService
    include FastlaneCI::Logging
    attr_accessor :user_data_source

    def initialize(user_data_source: nil)
      unless user_data_source.nil?
        raise "user_data_source must be descendant of #{UserDataSource.name}" unless user_data_source.class <= UserDataSource
      end

      if user_data_source.nil?
        # Default to JSONUserDataSource
        logger.debug("user_data_source is new, using `ENV[\"data_store_folder\"]` if available, or `sample_data` folder")
        data_store_folder = ENV["data_store_folder"] # you can set it at runtime!
        data_store_folder ||= File.join(FastlaneCI::FastlaneApp.settings.root, "sample_data")
        user_data_source = JSONUserDataSource.create(json_folder_path: data_store_folder)
      end

      self.user_data_source = user_data_source
    end

    #####################################################
    # @!group Users Logic
    #####################################################

    def users
      user_data_source.users
    end

    def create_user!(id: nil, email: nil, password: nil)
      email = email.strip

      unless self.user_data_source.user_exist?(email: email)
        logger.debug("creating account #{email}")
        provider_credential = GitHubProviderCredential.new(email: email)
        return self.user_data_source.create_user!(id: id, email: email, password: password, provider_credential: provider_credential)
      end

      logger.debug("account #{email} already exists!")
      return nil
    end

    def update_user!(user: nil)
      self.user_data_source.update_user!(user: user)
    end

    # @return [User]
    def find_user(id: nil)
      self.user_data_source.find_user(id: id)
    end

    def login(email: nil, password: nil, ci_config_repo: nil)
      email = email.strip

      logger.debug("attempting to login user with email #{email}")
      user = self.user_data_source.login(email: email, password: password)
      return user
    end

    #####################################################
    # @!group Provider Credential Logic
    #####################################################

    # Creates a new provider credential, and adds it to the User's provider
    # credentials array
    def create_provider_credential!(
      user_id: nil, id: nil, email: nil, api_token: nil, full_name: nil
    )
      provider_credential = GitHubProviderCredential.new(
        id: id, email: email, api_token: api_token, full_name: full_name
      )
      user = Services.user_service.find_user(id: user_id)

      if user.nil?
        logger.error("Can't create provider credential for user, since user does not exist.")
      else
        new_user = User.new(
          id: user.id,
          email: user.email,
          password_hash: user.password_hash,
          provider_credentials: user.provider_credentials.push(provider_credential)
        )
        Services.user_service.update_user!(user: new_user)
      end
    end

    # Look-up the user by `user_id` and updates the provider credential
    # associated with the provider credential `id`
    def update_provider_credential!(
      user_id: nil, id: nil, email: nil, api_token: nil, full_name: nil
    )
      provider_credential = GitHubProviderCredential.new(
        email: email, api_token: api_token, full_name: full_name
      )
      user = Services.user_service.find_user(id: user_id)

      if user.nil?
        logger.error("Can't update provider credential for user, since user does not exist.")
      else
        # Delete the old credential, and push on the new one
        new_provider_credentials = user.provider_credentials
                                       .delete_if { |credential| credential.id == id }
                                       .push(provider_credential)

        new_user = User.new(
          id: user.id,
          email: user.email,
          password_hash: user.password_hash,
          provider_credentials: new_provider_credentials
        )
        Services.user_service.update_user!(user: new_user)
      end
    end
  end
end
