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

manual_key <- "RGAPI-ea9dd280-3e04-456c-823d-9ab95eaf76f8"
api_end <- paste("?api_key=", manual_key, sep='')

regionList <- c("NA1","KR","BR1","OC1", "JP1", "RU", "EUN1", "EUW1", "TR1", "LA1", "LA2")

library(shiny)
ui <- fluidPage(
  titlePanel("League of Legends statstics comparator"),
  
  textInput(inputId = "name", label = "Enter summoner name: "),
  selectInput(inputId = "region", label = "Select your region: ", choice = regionList),
  #textInput(inputId = "apiKey", label = "Enter league Api key: "),
  
  actionButton("submit", "Go!"),
  
  tableOutput(outputId = "stats"),
  textOutput("submitMessage"),
  textOutput("error")
)

# install.packages("jsonlite")

#
#Right now we're working under the assumption the name
#and API key are correct
#Error checking would involve pulling the json and reading the response code
#

server <- function(input, output, session) {
  
  observeEvent(input$submit, {
    output$submitMessage <- renderText({
      paste(input$name, "'s stats are now being compared to challenger league average stats")
    })
    
    api_start <- paste("https://", input$region, ".api.riotgames.com/lol", sep='')
    summoner_link <- paste(api_start, "/summoner/v4/summoners/by-name/", input$name, api_end, sep='')
    
    sum_text<- paste("looking at user: ", input$name, sep='')
    print(sum_text)
    
    if(http_error(GET(summoner_link))){
      stop("summoner name does not exist, or you have selected the wrong region")
      print(http_status(GET(summoner_link)))
    }
    
    # #use summoner name to get accountID
    s_json<-fromJSON(summoner_link, flatten = TRUE)
    s_df = as.data.frame(s_json)
    accID <- s_df[["accountId"]]
    
    
    #use accountID to get match_list json file (list of match numbers a player participated in)
    acc_link <- paste(api_start, "/match/v4/matchlists/by-account/", accID, api_end, sep='')
    
    if(http_error(GET(acc_link))){
      stop("something is wrong with the account link")
      print(http_status(GET(acc_link)))
    }
    
    ml_json<-fromJSON(acc_link, flatten = TRUE)
    ml_df = as.data.frame(ml_json)
    match_list<-ml_df[["matches.gameId"]]
    
    dbGetQuery (con, "drop table if exists averages")
    dbGetQuery(con, "create table averages (Vision_Score int, Longest_Time_Spent_Alive int, Kills int, Wards_Killed int, Dragons_Killed int, Assists int)")
    dbGetQuery(con, "insert into averages select avg(Vision_Score),avg(Longest_Time_Spent_Alive), avg(Kills), avg(Wards_Killed), avg(Dragons_Killed), avg(Assists) from match_information;")
    dbGetQuery (con, "drop table if exists temp_averages")
    dbGetQuery (con, "drop table if exists temp_player")
    dbGetQuery(con, "create table temp_player (row_names text, GameID double, AccountID text, ParticipantID bigint(20), ChampionID bigint(20), Vision_Score bigint(20), Longest_Time_Spent_Alive bigint(20), Kills bigint(20), Wards_Killed bigint(20), Dragons_Killed bigint(20), Assists bigint(20), Role text, Lane text)")
    
    match_numbers <- 1
    for (gameID in match_list) {
      match_num <- paste(api_start, "/match/v4/matches/", gameID, api_end, sep = '')
      
      #print(match_num)
      if(http_error(GET(match_num))){
        stop("something failed in getting the match data")
        print(http_status(GET(match_num)))
      }
      
      m_json <- fromJSON(match_num, flatten = TRUE)
      m_df = as.data.frame(m_json)
      
      season <- m_df[["seasonId"]]
      if(!(identical(as.character(season[[1]]), "13"))){
        #print("AM LESS THAN 13")
        break
      }
      
      gameMode <- m_df[["gameMode"]]
      #print(as.character(gameMode[[1]]))
      if(identical(as.character(gameMode[[1]]), "CLASSIC"))
      {
        game_text <- paste("looking at match number: ", gameID, sep='')
        print(game_text)
        m_var = c("gameId", "participantIdentities.player.accountId", "participantIdentities.participantId", "participants.championId", "participants.stats.visionScore", "participants.stats.longestTimeSpentLiving", "participants.stats.kills", "participants.stats.wardsKilled", "teams.dragonKills", "participants.stats.assists", "participants.timeline.role","participants.timeline.lane")
        #"participants.timeline.csDiffPerMinDeltas.0.10", "participants.timeline.goldDiffPerMinDeltas.0.10", "participants.timeline.xpDiffPerMinDeltas.0.10")
        match_data <- m_df[m_var]
        colnames(match_data) <- c("GameID", "AccountID", "ParticipantID", "ChampionID", "Vision_Score", "Longest_Time_Spent_Alive", "Kills", "Wards_Killed", "Dragons_Killed", "Assists", "Role", "Lane")#, "cs_Diff_Per_Min", "gold_Diff_Per_Min", "xp_Diff_Per_Min")
        dbWriteTable(con, "temp_player", match_data, append = TRUE)
        #print("IS CLASSIC")
      }
      Sys.sleep(1)
      
      if(match_numbers >= 10){
        break;
      }
      match_numbers <- match_numbers + 1;
    }
    
    query <- paste("create table temp_averages (select avg(Vision_Score), avg(Longest_Time_Spent_Alive), avg(Kills), avg(Wards_Killed), avg(Dragons_Killed), avg(Assists) from temp_player where AccountID = \"", accID, "\")", sep = '')
    dbGetQuery(con, query)
    dbGetQuery(con, "insert into averages select * from temp_averages")
    
    #Loop through match numbers gained from last part use json per match to average player stats
    #Note: there might need to be a delay, because we're limited to 20 queries a second
    
    output$stats <- renderTable({
      main <- "Comparison of player to challenger league average"
      myquery <- "select * from averages"
      df = dbGetQuery(con, myquery)
      df
    })
    
  })
}
shinyApp(ui = ui, server = server)

