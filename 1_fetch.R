source("1_fetch/src/get_nwis_sites.R")
source("1_fetch/src/get_daily_nwis_data.R")
source("1_fetch/src/get_inst_nwis_data.R")
source("1_fetch/src/find_sites_multipleTS.R")
source('1_fetch/src/get_nlcd_LC.R')
source("1_fetch/src/get_nhdplusv2.R")
source('1_fetch/src/download_tifs_annual.R')
source("1_fetch/src/get_gf.R")
source("1_fetch/src/fetch_sb_data.R")
source("1_fetch/src/fetch_nhdv2_attributes_from_sb.R")
source("1_fetch/src/download_file.R")
source("1_fetch/src/munge_reach_attr_tbl.R")

p1_targets_list <- list(
  
  # Load harmonized WQP data product for discrete samples
  tar_target(
    p1_wqp_data,
    readRDS(file = "1_fetch/in/DRB.WQdata.rds")
  ),
  
  # Identify NWIS sites with SC data 
  tar_target(
    p1_nwis_sites,
    {
      dummy <- dummy_date
      get_nwis_sites(drb_huc8s,pcodes_select,site_tp_select,stat_cd_select)
    }
  ),
  
  # Subset daily NWIS sites
  tar_target(
    p1_nwis_sites_daily,
    p1_nwis_sites %>%
      # retain "dv" sites that contain data records after user-specified {earliest_date}
      filter(data_type_cd=="dv",!(site_no %in% omit_nwis_sites),end_date > earliest_date) %>%
      # for sites with multiple time series (ts_id), retain the most recent time series for site_info
      group_by(site_no) %>% arrange(desc(end_date)) %>% slice(1)
  ),
  
  # Download NWIS daily data
  tar_target(
    p1_daily_data,
    get_daily_nwis_data(p1_nwis_sites_daily,parameter,stat_cd_select,start_date=earliest_date,end_date=dummy_date),
    pattern = map(p1_nwis_sites_daily)
  ),
  
  # Subset NWIS sites with instantaneous (sub-daily) data
  tar_target(
    p1_nwis_sites_inst,
    p1_nwis_sites %>%
      # retain "uv" sites that contain data records after user-specified {earliest_date}
      filter(data_type_cd=="uv",!(site_no %in% omit_nwis_sites),end_date > earliest_date) %>%
      # for sites with multiple time series (ts_id), retain the most recent time series for site_info
      group_by(site_no) %>% arrange(desc(end_date)) %>% slice(1)
  ),
  
  # Create log file to track sites with multiple time series
  tar_target(
    p1_nwis_sites_inst_multipleTS_csv,
    find_sites_multipleTS(p1_nwis_sites,earliest_date,dummy_date,omit_nwis_sites,"3_visualize/log/summary_multiple_inst_ts.csv"),
    format = "file"
  ),

  # Download NWIS instantaneous data
  tar_target(
    p1_inst_data,
    get_inst_nwis_data(p1_nwis_sites_inst,parameter,start_date=earliest_date,end_date=dummy_date),
    pattern = map(p1_nwis_sites_inst)
  ),

  tar_target(
    p1_reaches_shp_zip,
    # [Jeff] I downloaded this manually from science base: 
    # https://www.sciencebase.gov/catalog/item/5f6a285d82ce38aaa244912e
    # Because it's a shapefile, it's not easily downloaded using sbtools
    # like other files are (see https://github.com/USGS-R/sbtools/issues/277).
    # Because of that and since it's small (<700 Kb) I figured it'd be fine to
    # just include in the repo and have it loosely referenced to the sb item ^
    "1_fetch/in/study_stream_reaches.zip",
    format = "file"
  ),

  # Unzip zipped shapefile
  tar_target(
    p1_reaches_shp,
    {shapedir = "1_fetch/out/study_stream_reaches"
    # `shp_files` is a vector of all files ('dbf', 'prj', 'shp', 'shx')
    shp_files <- unzip(p1_reaches_shp_zip, exdir = shapedir)
    # return just the .shp file
    grep(".shp", shp_files, value = TRUE)},
    format = "file"
  ),
  
  # read shapefile into sf object
  tar_target(
    p1_reaches_sf,
    st_read(p1_reaches_shp,quiet=TRUE)
  ),

  # Download NHDPlusV2 flowlines for DRB
  tar_target(
    p1_nhdv2reaches_sf,
    get_nhdv2_flowlines(drb_huc8s)
  ),  
  
  # Download edited HRU polygons from https://github.com/USGS-R/drb-network-prep
  tar_target(
    p1_catchments_edited_gpkg,
    download_file(GFv1_HRUs_edited_url,
                  fileout = "1_fetch/out/GFv1_catchments_edited.gpkg", 
                  mode = "wb", quiet = TRUE),
    format = "file"
  ),
  
  # Read in edited HRU polygons
  tar_target(
    p1_catchments_edited_sf,
    sf::st_read(dsn = p1_catchments_edited_gpkg, layer = "GFv1_catchments_edited", quiet = TRUE) %>%
      mutate(PRMS_segid_split_col = PRMS_segid) %>%
      separate(col = PRMS_segid_split_col, sep = '_', into =c('prms_subseg_seg', "PRMS_segment_suffix")) %>%
      mutate(hru_area_km2 = hru_area_m2/10^6,
             prms_subseg_seg = case_when(PRMS_segid == '3_1' ~ '3_1',
                                          PRMS_segid == '3_2' ~ '3_2',
                                          PRMS_segid == '8_1' ~ '8_1',
                                          PRMS_segid == '8_2' ~ '8_2',
                                          PRMS_segid == '51_1' ~ '51_1',
                                          PRMS_segid == '51_2' ~ '51_2',
                                          TRUE ~ prms_subseg_seg)) %>%
      select(-hru_area_m2, -PRMS_segment_suffix)
  ),
  
  # Download DRB network attributes
  # Retrieved from: https://www.sciencebase.gov/catalog/item/5f6a289982ce38aaa2449135
  tar_target(
    p1_prms_reach_attr_csvs,
    download_sb_file(sb_id = "5f6a289982ce38aaa2449135",
                     file_name = c("reach_attributes_drb.csv","distance_matrix_drb.csv","sntemp_inputs_outputs_drb.zip"),
                     out_dir="1_fetch/out"),
    format="file"
  ),
  
  # Read DRB reach attributes with all _1 segments for _2 reaches
  tar_target(
    p1_prms_reach_attr,
    munge_reach_attr_table(p1_prms_reach_attr_csvs)
  ),
  
  # Read DRB network adjacency matrix
  tar_target(
    p1_ntw_adj_matrix,
    read_csv(grep("distance_matrix",p1_prms_reach_attr_csvs,value=TRUE),show_col_types = FALSE)
  ),
  
  # Unzip DRB SNTemp Inputs-Outputs from temperature project
  tar_target(
    p1_sntemp_inputs_outputs_csv,
    unzip(zipfile = grep("sntemp_inputs_outputs",p1_prms_reach_attr_csvs,value=TRUE), exdir = "1_fetch/out", overwrite = TRUE),
    format = "file"
  ),
  
  # Read DRB SNTemp Inputs-Outputs from temperature project
  tar_target(
    p1_sntemp_inputs_outputs,
    read_csv(p1_sntemp_inputs_outputs_csv,show_col_types = FALSE)
  ),

  # Read in all nlcd data from 2001-2019 
  # Note: NLCD data must already be downloaded locally and manually placed in NLCD_LC_path ('1_fetch/in/NLCD_final/')
  tar_target(
    p1_NLCD_LC_data,
    read_subset_LC_data(LC_data_folder_path = NLCD_LC_path,
                        Comids_in_AOI_df = p1_nhdv2reaches_sf %>% st_drop_geometry() %>% select(COMID),
                        Comid_col = 'COMID', NLCD_type = NULL)
  ),
    
  # Download other NLCD 2011 datasets 
  tar_target(
    p1_NLCD2011_data_zipped, 
    download_NHD_data(sb_id = sb_ids_NLCD2011,
                      out_path = '1_fetch/out',
                      downloaded_data_folder_name = NLCD2011_folders,
                      output_data_parent_folder = 'NLCD_LC_2011_Data'),
    format = 'file'
  ),
  
  # Unzip all NLCD downloaded datasets 
  ## Note - this returns a string or vector of strings of data path to unzipped datasets 
  tar_target(
    p1_NLCD2011_data_unzipped,
    unzip_NHD_data(downloaded_data_folder_path = p1_NLCD2011_data_zipped,
                   create_unzip_subfolder = T),
    format = 'file'
  ),
  
  # Read in NLCD datasets and subset by comid in DRB
  ## Note that this returns a vector of dfs if more than one NLCD data is in the p1_NLCD_data_unzipped
  tar_target(
    p1_NLCD2011_data,
    read_subset_LC_data(LC_data_folder_path = p1_NLCD2011_data_unzipped, 
                        Comids_in_AOI_df = p1_nhdv2reaches_sf %>% st_drop_geometry() %>% select(COMID), 
                        Comid_col = 'COMID')
  ),

  # Downlaod FORE-SCE backcasted LC tif files and subset to years we want
  ## Retrieved from: https://www.sciencebase.gov/catalog/item/605c987fd34ec5fa65eb6a74
  ## Note - only file #1 DRB_Historical_Reconstruction_1680-2010.zip will be extracted
  tar_target(
    p1_FORESCE_backcasted_LC, 
    download_tifs(sb_id = '605c987fd34ec5fa65eb6a74',
                  filename = 'DRB_Historical_Reconstruction_1680-2010.zip',
                  download_path = '1_fetch/out',
                  ## Subset downloaded tifs to only process the  years that are relevant model
                  year = FORESCE_years,
                  name_unzip_folder = NULL,
                  overwrite_file = TRUE,
                  name = FORESCE_years), 
    format = 'file'
  ),
  
  #Targets for the land cover reclassification .csv files
  tar_target(
    p1_NLCD_reclass_table_csv, 
    '1_fetch/in/Legend_NLCD_Land_Cover.csv',
    format = 'file'
  ),
  tar_target(
    p1_FORESCE_reclass_table_csv, 
    '1_fetch/in/Legend_FORESCE_Land_Cover.csv',
    format = 'file'
  ),
  tar_target(
    p1_NLCD_reclass_table, 
    read_csv(p1_NLCD_reclass_table_csv, show_col_types = FALSE)
  ),
  tar_target(
    p1_FORESCE_reclass_table, 
    read_csv(p1_FORESCE_reclass_table_csv, show_col_types = FALSE)
  ),
  
  # Downlaod Road Salt accumulation data for the drb
  ## Retrieved from: https://www.sciencebase.gov/catalog/item/5b15a50ce4b092d9651e22b9
  ## Note - only zip file named 1992_2015.zip will be extracted
  tar_target(
    p1_rdsalt, 
    download_tifs(sb_id = '5b15a50ce4b092d9651e22b9',
                  filename = '1992_2015.zip',
                  download_path = '1_fetch/out',
                  overwrite_file = T,
                  ## no year subsetting here as all years with rdsalt data are relevant here
                  year = NULL,
                  name_unzip_folder = 'rd_salt'), 
             format = 'file'
  ),

  # Csv of variables from the Wieczorek dataset that are of interest 
  tar_target(
    p1_vars_of_interest_csv,
    '1_fetch/in/NHDVarsOfInterest.csv',
    format = 'file'
  ),

  # Variables from the Wieczorek dataset that are of interest 
  # use tar_group to define row groups based on ScienceBase ID; row groups facilitate
  # branching over subsets of the VarsOfInterest table in downstream targets
  tar_target(
    p1_vars_of_interest,
    read_csv(p1_vars_of_interest_csv, show_col_types = FALSE) %>%
      # Parse sb_id from sb link 
      mutate(sb_id = str_extract(Science.Base.Link,"[^/]*$")) %>%
      # Omit NADP and LandCover rows since we are loading those separately
      filter(!Theme %in% c('Chemical', 'Land Cover')) %>%
      group_by(sb_id) %>%
      tar_group(),
    iteration = "group"
  ),

  # Map over variables of interest to download NHDv2 attribute data from ScienceBase
  tar_target(
    p1_vars_of_interest_downloaded_csvs,
    fetch_nhdv2_attributes_from_sb(vars_item = p1_vars_of_interest, save_dir = "1_fetch/out", 
                                   comids = p1_nhdv2reaches_sf$COMID, delete_local_copies = TRUE),
    pattern = map(p1_vars_of_interest),
    format = "file"
  ),
  
  # # download NADP data
  # ## source: https://www.sciencebase.gov/catalog/item/57e2ac2fe4b0908250045981
  tar_target(
    p1_NADP_data_zipped,
    download_NHD_data(sb_id = NADP_sb_id,
                      out_path = '1_fetch/out',
                      downloaded_data_folder_name = 'NADP_Data'),
    format = 'file'
  ),

  # unzip NADP data
  tar_target(
    p1_NADP_data_unzipped,
    unzip_NHD_data(p1_NADP_data_zipped),
    format = 'file'
  ),
  
  # Download monthly natural baseflow for the DRB
  # from Miller et al. 2021: https://www.sciencebase.gov/catalog/item/6023e628d34e31ed20c874e4
  tar_target(
    p1_natural_baseflow_zip,
    download_sb_file(sb_id = "6023e628d34e31ed20c874e4",
                     file_name = "baseflow_partial_model_pred_XX.zip",
                     out_dir="1_fetch/out"),
    format = "file"
  ),
  
  # Unzip monthly natural baseflow file
  tar_target(
    p1_natural_baseflow_csv,
    {unzip(zipfile=p1_natural_baseflow_zip,exdir = dirname(p1_natural_baseflow_zip),overwrite=TRUE)
     file.path(dirname(p1_natural_baseflow_zip), list.files(path = dirname(p1_natural_baseflow_zip),pattern = "*baseflow.*.csv"))
      },
    format = "file"
  )
)
  