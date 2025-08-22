import pandas as pd
import xarray as xr
import numpy as np
import os

# Paths
study_areas = ["Rhine", "Yangtze", "LaPlata", "Indus"]
crops = ["mainrice", "maize", "secondrice", "soybean", "springwheat", "winterwheat"]

for study in study_areas:
    # Load precipitation file for basin
    pre_path = f"/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/{study}/Meteo/Prec_daily.nc"
    pre_ds = xr.open_dataset(pre_path)  # should have dims time, lat, lon
    pre_da = pre_ds["Prec"]  # adjust variable name if needed
    
    for crop in crops:
        csv_file = f"/lustre/nobackup/WUR/ESG/zhou111/3_RQ1_Model_Outputs/S1/{study}_{crop}_daily.csv"
        if not os.path.exists(csv_file):
            continue
        
        print(f"Processing {study} - {crop}")

        # Load crop daily CSV
        df = pd.read_csv(csv_file)
        
        # Compute EvaTrans
        df["EvaTrans"] = (df["Transpiration"] + df["EvaWater"] + df["EvaSoil"])*10

        # Build datetime
        df["time"] = pd.to_datetime(df["Year"].astype(str), format="%Y") + pd.to_timedelta(df["Day"] - 1, unit="D")
        
        # Convert to xarray directly
        crop_ds = (
            df.set_index(["time", "Lat", "Lon"])
              .EvaTrans
              .to_xarray()
              .rename({"Lat": "lat", "Lon": "lon"})
        )

        # Reindex to precipitation grid and time (fill missing with 0 = no crop planted)
        crop_ds = crop_ds.reindex_like(pre_da, fill_value=0)

        # Compute water deficit
        deficit = xr.apply_ufunc(
            lambda ev, pr: np.maximum(ev - pr, 0),
            crop_ds, pre_da,
            dask="parallelized",
            output_dtypes=[float]
        )
        deficit.name = "WaterDeficit"

        # Resample to monthly sum (time at first day of month)
        deficit_monthly = deficit.resample(time="MS").sum()

        # Save NetCDF
        out_nc = f"/lustre/nobackup/WUR/ESG/zhou111/3_RQ1_Model_Outputs/S1/{study}_{crop}_Deficit_monthly.nc"
        deficit_monthly.to_netcdf(out_nc)
        print(f"Saved: {out_nc}")
