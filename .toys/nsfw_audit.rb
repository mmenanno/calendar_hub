# frozen_string_literal: true

desc("Audit and optionally fix mismatched NSFW game updates (F95 thread-id)")
flag :fix, default: false

def run
  require_relative "../config/environment"
  ENV["DISABLE_FLARE_WARMUP"] = "1"

  mismatches = []
  NSFWGameUpdate.includes(:nsfw_game).find_each do |update|
    next unless update.site == "F95zone"

    game = update.nsfw_game
    next if game.nil?

    gid = NSFW::URLUtils.f95_thread_id(game.url)
    uid = NSFW::URLUtils.f95_thread_id(update.url)
    next if gid.present? && uid.present? && gid == uid

    mismatches << [update, game, gid, uid]
  end

  if mismatches.empty?
    puts("No mismatched updates found")
    return
  end

  puts("Found #{mismatches.size} mismatched updates:")
  mismatches.each do |update, game, gid, uid|
    puts("Update ##{update.id} (#{update.url}) -> Game ##{game.id} (#{game.url}) [#{uid} != #{gid}]")
  end

  return unless fix

  puts("Attempting to re-associate...")
  mismatches.each do |update, _game, _gid, _uid|
    target = NSFWGame.find_by(url: update.url)
    if target.nil? && update.site == "F95zone"
      # Fallback by F95 thread id
      uid = NSFW::URLUtils.f95_thread_id(update.url)
      target = NSFWGame.where(site: "F95zone").detect do |g|
        NSFW::URLUtils.f95_thread_id(g.url) == uid
      end
    end
    if target
      # If update matches target game and values equal current, delete the no-op update
      if target.site == update.site && target.version == update.version && target.url == update.url && target.developer == update.developer && target.game_name == update.game_name
        update.destroy!
        puts("Deleted no-op update ##{update.id} for Game ##{target.id}")
        next
      end
      update.update!(nsfw_game: target)
      puts("Updated ##{update.id} -> Game ##{target.id}")
    else
      puts("No target game found for update ##{update.id} (#{update.url})")
    end
  end
end
