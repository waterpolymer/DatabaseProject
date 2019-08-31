library("jsonlite")
library("tidyr")


#manual input of information
sql_user <- "root"
sql_pass <- "cat"
sql_dbname <- "cyes435"
sql_host <- "localhost"

library(RMySQL)
library(dbConnect)
library(httr)
#establish shorthand connection to my input database
con = dbConnect(RMySQL::MySQL(), user = sql_user, password = sql_pass, dbname = sql_dbname, host = sql_host)
#con = dbConnect(RMySQL::MySQL(), user = "root", password = "cat", dbname = "cyes435", host = "localhost")

#c_ stands for challenger


challenger_region <- "na1"
manual_key <- "RGAPI-ea9dd280-3e04-456c-823d-9ab95eaf76f8"
api_end <- paste("?api_key=", manual_key, sep='')
api_start <- paste("https://", challenger_region, ".api.riotgames.com/lol", sep='')

challenger_link <- paste(api_start, "/league/v4/challengerleagues/by-queue/RANKED_SOLO_5x5", api_end, sep='')
c_json = fromJSON(challenger_link, flatten = TRUE)
c_df = as.data.frame(c_json)
c_vars <- c("entries.summonerName", "entries.inactive", "entries.rank", "queue")
c_data <- c_df[c_vars]
colnames(c_data) <- c("Summoner", "Inactive", "Rank", "Queue")


dbWriteTable(con, "challengers", c_data, overwrite = TRUE, append = FALSE)

c_names <- c_df[["entries.summonerName"]]

name_counter <- 1
for(name in c_names){
  summoner_link <- paste(api_start, "/summoner/v4/summoners/by-name/", name, api_end, sep='')
  
  summoner_link <- gsub(" ", "", summoner_link, fixed = TRUE)
  sum_text <- paste("looking at player: ", name, sep='')
  print(sum_text)
  
  if(http_error(GET(summoner_link))){
    stop("something is wrong with the summoner_json")
    print(http_status(GET(summoner_link)))
  }
  
  s_json <- fromJSON(summoner_link, flatten = TRUE)
  s_df = as.data.frame(s_json)
  s_vars <- c("name", "puuid", "summonerLevel", "accountId", "id")
  s_data <- s_df[s_vars]
  colnames(s_data) <- c("Summoner", "puuid", "Level", "AccountID", "SummonerID")
  
  if(name_counter == 1){
    dbWriteTable(con, "players", s_data, overwrite = TRUE, append = FALSE)
  }else{
    dbWriteTable(con, "players", s_data, overwrite = FALSE, append = TRUE)
  }
  
  
  accID <- s_df[["accountId"]]

  acc_link <- paste(api_start, "/match/v4/matchlists/by-account/", accID, api_end, sep='')
  ml_json = fromJSON(acc_link, flatten = TRUE)
  ml_df = as.data.frame(ml_json)
  ml_vars <- c("matches.lane", "matches.gameId", "matches.champion", "matches.platformId", "matches.season", "matches.queue", "matches.role")
  ml_data <- ml_df[ml_vars]
  colnames(ml_data) <- c("Lane", "GameID", "ChampionID", "PlatformID", "Season", "Queue", "Role")
  
  if(name_counter == 1){
    dbWriteTable(con, "matches", ml_data, overwrite = TRUE, append = FALSE)
  }else{
    dbWriteTable(con, "matches", ml_data, overwrite = FALSE, append = TRUE)
  }
  match_list <- ml_df[["matches.gameId"]]
  
  game_number <- 1
  for(gameID in match_list){
    match_link <- paste(api_start, "/match/v4/matches/", gameID, api_end, sep = '')
    match_text <- paste("getting information from gameId: ", gameID, sep='')
    print(match_text)
    
    if(http_error(GET(match_link))){
      stop("something failed in getting the match data")
      print(http_status(GET(match_link)))
    }
    
    m_json = fromJSON(match_link, flatten = TRUE)
    m_df = as.data.frame(m_json)
    
    season <- m_df[["seasonId"]]
    #print(as.character(season[[1]]))
    if(!(identical(as.character(season[[1]]), "13"))){
      #print("AM LESS THAN 13")
      break
    }
    
    gameMode <- m_df[["gameMode"]]
    if(identical(as.character(gameMode[[1]]), "CLASSIC"))
    {
      m_var = c("gameId", "participantIdentities.player.accountId", "participantIdentities.participantId", "participants.championId", "participants.stats.visionScore", "participants.stats.longestTimeSpentLiving", "participants.stats.kills", "participants.stats.wardsKilled", "teams.dragonKills", "participants.stats.assists", "participants.timeline.role","participants.timeline.lane")
      m_data <- m_df[m_var]
      colnames(m_data) <- c("GameID", "AccountID", "ParticipantID", "ChampionID", "Vision_Score", "Longest_Time_Spent_Alive", "Kills", "Wards_Killed", "Dragons_Killed", "Assists", "Role", "Lane")#, "cs_Diff_Per_Min", "gold_Diff_Per_Min", "xp_Diff_Per_Min")
      
      if(name_counter == 1){
        dbWriteTable(con, "match_information", m_data, overwrite = TRUE, append = FALSE)  
      }else{
        dbWriteTable(con, "match_information", m_data, overwrite = FALSE, append = TRUE)  
      }
      
    }
    
    #only checks last 10 games played by each challenger
    if(game_number >= 3){
      break
    }
    
    game_number <- game_number + 1
    Sys.sleep(3)
  }
  name_counter <- name_counter + 1
  
  if(name_counter >= 10){
    break
  }
}



#last 3 columns have 2 children, it complicates selecting specific columns

#dbGetQuery(con, "drop table if exists c_averages")
#dbGetQuery(con, "create table c_averages (Vision_Score int, Longest_Time_Spent_Alive int, Kills int, Wards_Killed int, Dragons_Killed int, Assists int)")
#dbGetQuery(con, "insert into c_averages select avg(Vision_Score),avg(Longest_Time_Spent_Alive), avg(Kills), avg(Wards_Killed), avg(Dragons_Killed), avg(Assists) from match_information;")