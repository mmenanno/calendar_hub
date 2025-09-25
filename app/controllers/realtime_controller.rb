# frozen_string_literal: true

class RealtimeController < ApplicationController
  before_action :assign_stream

  def show
    @adapter = begin
      cfg = ActionCable.server.config.cable
      cfg.is_a?(Hash) ? (cfg[:adapter] || cfg["adapter"]) : nil
    rescue
      nil
    end
  end

  def ping
    Turbo::StreamsChannel.broadcast_replace_to(
      @stream,
      target: "realtime_probe",
      partial: "realtime/payload",
      locals: { time: Time.current, note: t("realtime.pong") },
    )
    respond_to do |format|
      format.turbo_stream { head(:ok) }
      format.html { redirect_to(realtime_path(token: @token), notice: t("flashes.realtime.broadcast_sent")) }
    end
  end

  private

  def assign_stream
    @token = params[:token].presence || session[:realtime_token] || SecureRandom.hex(6)
    session[:realtime_token] = @token
    @stream = "realtime_test_#{@token}"
  end
end
