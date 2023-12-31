# Creator: Amin Shoari Nejad

library(lubridate)
library(tidyverse)
library(leaflet)
library(tigris)
library(spdplyr)
library(shinycssloaders)


# Reading data
eircodes <- readRDS("data/eircodes.rds")
country_excess_mortality <- readRDS("data/country_excess_mortality.rds")
counties_excess_mortality <- readRDS("data/counties_excess_mortality.rds")
df_mortality_all <- readRDS("data/df_mortality_all.rds")
last_update <- format(max(country_excess_mortality$Date), "%b %d, %Y")


ui <- fluidPage(
  titlePanel("Excess postings to RIP.ie"),
  hr(),
  p(paste0("Last update: ", last_update)),
  navbarPage(
    "",
    tabPanel(
      "Regional excess mortality estimate",
      mainPanel(
        p("NOTE: To check region-specific excess mortality click on a map region."),
        leafletOutput("view") %>% withSpinner(color = "#084C95"),
        hr(),
        width = 12
      )
    ), # End of Map tabpanel
    
    tabPanel(
      "National excess mortality estimate",
      mainPanel(
        fluidPage(
          fluidRow(
            # p("Under development."),
            plotlyOutput("plot3") %>% withSpinner(color = "#084C95"),
            hr()
          )
        ),
        width = 12
      ) # End of national excess panel
    ),


    tabPanel(
      "Heatmap by region",
      mainPanel(
        fluidPage(
          fluidRow(

            # p("Under development."),
            plotlyOutput("plot4", height = "720px") %>% withSpinner(color = "#084C95"),
            hr()
          )
        ),
        width = 12
      )
    ),
    tabPanel(
      "About",
      fluidPage(
        fluidRow(
          p(HTML("<p> This app is developed for tracking excess mortality in the Republic of Ireland. The excess mortality (p value) calculation is done following the method explained <a href='https://ourworldindata.org/excess-mortality-covid'> here</a>. <p> The data used by this app is scraped from RIP.ie on a daily basis enabling the app to provide near real-time information on excess mortality. However, please note that the data is not officially confirmed by authorities. <p>"))
        )
      )
    ) # End of tabPanels
  ) # End of navbar
) # End of UI


server <- function(input, output) {
  output$view <- renderLeaflet({
    df2 <- counties_excess_mortality %>%
      group_by(Group) %>%
      filter(Date == max(Date) - 1) # Subtract one to stop fractional days being plotted

    df2 <- geo_join(eircodes, df2, "Group", "Group")

    df2 <- df2 %>% dplyr::mutate(
      pop1 = case_when(
        as.character(df2$Group) != as.character(df2$Descriptor) ~ paste0(
          "Excess: ", df2$value, "% in ", stringr::str_to_title(df2$Group), " including ",
          stringr::str_to_title(df2$Descriptor)
        ),
        TRUE ~ paste0("Excess: ", df2$value, "% in ", stringr::str_to_title(df2$Group))
      ),
      pop2 = case_when(
        as.character(df2$Group) != as.character(df2$Descriptor) ~ paste0(
          Monthly_Notices, " at ", stringr::str_to_title(df2$Group),
          " including ", stringr::str_to_title(df2$Descriptor)
        ),
        TRUE ~ paste0(Monthly_Notices, " in ", stringr::str_to_title(df2$Group))
      )
    )

    # Create colour palette that goes through 0
    q0 <- round(ecdf(df2$value)(0), 2) * 100
    rc1 <- colorRampPalette(colors = c("#084C95", "white"), space = "Lab")(q0)
    rc2 <- colorRampPalette(colors = c("white", "darkred"), space = "Lab")(100 - q0)

    ## Combine the two color palettes
    rampcols <- c(rc1, rc2)
    pal <- colorNumeric(palette = rampcols, domain = df2$value)

    popup_sb <- df2$pop1

    leaflet() %>%
      addTiles() %>%
      setView(-7.5959, 53.5, zoom = 6) %>%
      addPolygons(
        data = df2, fillColor = ~ pal(df2$value), layerId = ~Descriptor,
        fillOpacity = 0.8,
        weight = 0.2,
        smoothFactor = 0.2,
        highlight = highlightOptions(
          weight = 5,
          color = "#666",
          fillOpacity = 0.2,
          bringToFront = TRUE
        ),
        label = popup_sb,
        labelOptions = labelOptions(
          style = list("font-weight" = "normal", padding = "3px 8px"),
          textsize = "15px",
          direction = "auto"
        )
      ) %>%
      addLegend(
        pal = pal, values = df2$value, title = "Excess mortality %", opacity = 0.7,
        labFormat = labelFormat(suffix = " %")
      ) %>%
      leaflet.extras::addResetMapButton() %>%
      leaflet.extras::addSearchOSM(options = leaflet.extras::searchOptions(
        collapsed = T, zoom = 9, hideMarkerOnCollapse = T, moveToLocation = FALSE,
        autoCollapse = T
      ))
  })


  observeEvent(input$view_shape_click, { # Plotting excess mortality plots for each region after clicking on the map


    output$plot2 <- renderPlotly({
      m <- subset(eircodes, Descriptor == input$view_shape_click$id)

      df3 <- df_mortality_all %>% filter(Group == m$Group)


      # calculate reference levels:
      ref_level <- df3 %>%
        filter(Year < 2020 & Year >= 2015) %>%
        ungroup() %>%
        group_by(Group, Date) %>%
        summarize(Monthly_Notices = sum(Monthly_Notices)) %>%
        mutate(DOY = yday(Date)) %>%
        group_by(Group, DOY) %>%
        mutate(
          Ref_Level = mean(Monthly_Notices),
          Prev_Max = max(Monthly_Notices)
        )

      # Merging 2020 and one of the previous years (doesn't matter which one they have identical ref col)

      df2020 <- df3 %>% filter(Year > 2019)
      df_ref <- ref_level %>%
        ungroup() %>%
        filter(year(Date) == 2019) %>%
        select(DOY, Ref_Level, Prev_Max)

      counties_excess_mortality <- left_join(df2020, df_ref, "DOY")
      counties_excess_mortality <- counties_excess_mortality %>% mutate(value = round(100 * (Monthly_Notices - Ref_Level) / Ref_Level)) # Mortality rate change


      x <- eircodes$RoutingKey[which(eircodes$Group == m$Group)]
      x <- knitr::combine_words(x)

      plt1 <- ggplot() +
        geom_line(
          data = df3,
          aes(x = Date, y = Monthly_Notices, linetype = "2020"), color = "#084C95"
        ) +
        geom_line(
          data = counties_excess_mortality,
          aes(x = Date, y = Prev_Max, linetype = "Previous years' max"), color = "blue"
        ) +
        geom_line(
          data = counties_excess_mortality,
          aes(x = Date, y = Ref_Level, linetype = "Previous years' mean"), color = "darkblue"
        ) +
        facet_wrap(facets = vars(Group)) +
        ggtitle(paste0("Notices Posted in 2020 - Eircode: ", x)) +
        labs(x = "", y = "Monthly Notices") +
        theme(axis.text.x = element_text(angle = 90), legend.position = c(0.89, 0.85)) +
        scale_x_date(date_breaks = "1 month", date_labels = "%b", limits = c(as.Date("2020-01-01"), max(country_excess_mortality$Date))) +
        labs(linetype = "") +
        scale_linetype_manual(values = c("solid", "dotted", "dashed")) +
        theme_bw()



      p <- counties_excess_mortality %>% ggplot(aes(Date, value)) +
        geom_line(color = "#084C95") +
        ylab("Excess postings %") +
        geom_hline(yintercept = 0, linetype = "dotted") +
        ggtitle(paste0("Excess postings in ", stringr::str_to_title(m$Group), " relative to 2015-2019 mean")) +
        theme_bw()

      plt2 <- ggplotly(p)

      if (input$yscale == "percent") {
        final_plot <- plt2
      } else {
        final_plot <- plt1
      }

      final_plot
    })
  }) # End of Observation

  observeEvent(input$view_shape_click, {
    showModal(modalDialog(
      title = "",
      size = "l",
      footer = actionButton("close", "Close"),
      radioButtons("yscale", p("Choose the comparison method:"),
        choices = list("Percentage" = "percent", "Absolute" = "exact"), inline = TRUE
      ),
      plotlyOutput("plot2") %>% withSpinner(color = "#084C95")
    ))
  })


  observeEvent(input$close, { # Removing modal and erasing previous plot

    output$plot2 <- NULL
    removeModal()
  })


  # National excess morality plot:
  output$plot3 <- renderPlotly({
    national_plot <- country_excess_mortality %>% ggplot(aes(Date, value)) +
      geom_line(color = "#084C95") +
      ylab("Excess postings (%)") +
      geom_hline(yintercept = 0, linetype = "dotted") +
      ggtitle("Excess mortality in Ireland compared to 2015-2019") +
      theme_bw()

    ggplotly(national_plot)
  })

  # Creating heatmap:
  output$plot4 <- renderPlotly({
    df_heat <- counties_excess_mortality %>%
      na.omit() %>%
      group_by(Group, Month, Year) %>%
      summarise(
        Monthly_Notices = round(mean(Monthly_Notices)),
        Ref_Level = round(mean(Ref_Level))
      ) %>%
      mutate(
        exc = round(100 * (Monthly_Notices - Ref_Level) / Ref_Level),
        date = as.POSIXct(ym(paste0(Year, "-", Month)))
      )


    heatmap_plot <- df_heat %>%
      ggplot(aes(x = date, y = Group, fill = exc)) +
      geom_tile() +
      labs(y = NULL, fill = "Excess %") +
      scale_x_datetime(labels = scales::date_format("%Y %b"), breaks = unique(df_heat$date)) +
      scale_fill_gradient2(limits = c(-100, 100), high = "darkred", low = "#084C95", oob = scales::squish) +
      theme_bw() +
      theme(
        axis.text.y = element_text(size = 6),
        axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "Top",
      )


    ggplotly(heatmap_plot, tooltip = c("Region", "Excess"))
  })
}

# Run the application
shinyApp(ui = ui, server = server)
