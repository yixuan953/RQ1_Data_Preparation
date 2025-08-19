import os
import glob
import xarray as xr
import numpy as np

# Define basins and crops
basins = ["Indus", "Rhine", "LaPlata", "Yangtze"]

# Logical crop names and filename variations
crops = {
    "Mainrice": ["Mainrice", "mainrice"],
    "Secondrice": ["Secondrice", "rice", "secondrice"],
    "Maize": ["Maize", "maize"],
    "Soybean": ["Soybean", "soybean", "Soy"],
    "Wheat": ["Wheat", "winterwheat", "Winterwheat"]
}

# Map logical crop names to mask filenames
mask_name_map = {
    "Mainrice": "mainrice",
    "Secondrice": "secondrice",
    "Maize": "maize",
    "Soybean": "soybean",
    "Wheat": "winterwheat"
}

# Base directories
maxavg_dir = "/lustre/nobackup/WUR/ESG/zhou111/3_RQ1_Model_Outputs/S0/"
mask_dir_base = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"

# Loop over basins
for basin in basins:
    # Find all MaxAvg files for this basin
    maxavg_files = glob.glob(os.path.join(maxavg_dir, f"{basin}_*_MaxAvg.nc"))
    
    for maxavg_file in maxavg_files:
        # Determine which logical crop this file corresponds to
        basename = os.path.basename(maxavg_file)
        logical_crop = None
        for lcrop, variants in crops.items():
            if any(v.lower() in basename.lower() for v in variants):
                logical_crop = lcrop
                break
        
        if logical_crop is None:
            print(f"Cannot map {basename} to any logical crop")
            continue
        
        # Determine corresponding mask file
        mask_file = os.path.join(mask_dir_base, basin, "Mask", f"{mask_name_map[logical_crop]}_mask.nc")
        if not os.path.exists(mask_file):
            print(f"Mask file does not exist: {mask_file}")
            continue

        # Open MaxAvg file
        ds_maxavg = xr.open_dataset(maxavg_file)
        # Extract needed variables
        ds_vars = ds_maxavg[["TSUM1", "TSUM2", "Sow_date"]]

        # Open HA mask file
        ds_mask = xr.open_dataset(mask_file)
        if "HA" not in ds_mask:
            print(f"HA not found in {mask_file}")
            continue
        ds_vars["HA"] = ds_mask["HA"]

        # Save new combined mask
        save_dir = os.path.join(mask_dir_base, basin, "Mask")
        os.makedirs(save_dir, exist_ok=True)
        save_file = os.path.join(save_dir, f"{basin}_{mask_name_map[logical_crop]}_mask.nc")
        ds_vars.to_netcdf(save_file)
        print(f"Saved combined mask: {save_file}")
