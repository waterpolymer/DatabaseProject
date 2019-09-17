# DatabaseProject
A project using Riot API to compare the inputted user's stats to the average of the top 0.01% of users, also known as the challenger tier

The project was made using rstudio.

In order to run the program properly the user must: 
  * Replace database username, password, port, etc. information to their own database information
  * Generate their own riot api key (can be found here: https://developer.riotgames.com/)
  * Run the database_script.r first to set up the database
  * Run the shiny script last to dynamically query the riot api for statistic information
  
Note: The program only queries and averages the first 10 or so challenger players for a lower running time setting up the database, the value can be changed to incorperate a larger sample size. 
