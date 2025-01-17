class GraphqlController < ApplicationController
  # FIXME: in prod, make sure to observe proper CSRF behaviors
  skip_before_action :verify_authenticity_token

  # If accessing from outside this domain, nullify the session
  # This allows for outside API access while preventing CSRF attacks,
  # but you'll have to authenticate your user separately
  # protect_from_forgery with: :null_session

  def execute
    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]
    context = {current_user: current_user, session: session}
    result =
      InkindSchema.execute(
        query,
        variables: variables,
        context: context,
        operation_name: operation_name
      )
    render json: result
  rescue => e
    raise e unless Rails.env.development?

    handle_error_in_development(e)
  end

  private

  def current_user
    if bearer_token
      user_id = User.id_from_token(bearer_token)
      User.find(user_id)
    else
      super
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def bearer_token
    return session[:token] if session[:token]

    pattern = /^Bearer /
    header = request.headers["Authorization"]
    header.gsub(pattern, "") if header&.match(pattern)
  end

  # Handle variables in form data, JSON body, or a blank value
  def prepare_variables(variables_param)
    case variables_param
    when String
      variables_param.present? ? JSON.parse(variables_param) || {} : {}
    when Hash
      variables_param
    when ActionController::Parameters
      variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{variables_param}"
    end
  end

  def handle_error_in_development(error)
    logger.error error.message
    logger.error error.backtrace.join("\n")

    render json: {
      errors: [{message: error.message, backtrace: error.backtrace}],
      data: {}
    }, status: :internal_server_error
  end
end
