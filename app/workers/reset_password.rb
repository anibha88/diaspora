# frozen_string_literal: true

module Workers
  class ResetPassword < Base
    diaspora_queue :urgent

    def perform(user_id)
      User.find(user_id).send_reset_password_instructions!
    end
  end
end
