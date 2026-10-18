# frozen_string_literal: true

class PagesController < ActionController::Base
  layout "application"
  after_action { response.set_header("X-Demo-Pid", Process.pid.to_s) }

  def show
    render inertia: "Demo", props: { message: "Warmed before you arrive", release: WarmerDemo::RELEASE }
  end

  def health
    render plain: "ready"
  end
end
