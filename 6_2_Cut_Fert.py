import os
import xarray as xr

Crops = ["Rice", "Maize", "Soybean", "Wheat"]
StudyAreas = ["Yangtze", "LaPlata", "Indus", "Rhine"]

global_dir = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Fertilizer_1981-2016"
studyarea_dir = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"

for crop in Crops:
    global_file = os.path.join(global_dir, f"{crop}_fert_1981-2016.nc")
    print(f"Loading global file: {global_file}")
    ds_global = xr.open_dataset(global_file)

    for area in StudyAreas:
        print(f"Processing {crop} for {area}...")
        range_file = os.path.join(studyarea_dir, f"{area}/range.nc")
        ds_range = xr.open_dataset(range_file)

        # Assuming range.nc has lat_min, lat_max, lon_min, lon_max
        lat_min = ds_range.lat.min().item()
        lat_max = ds_range.lat.max().item()
        lon_min = ds_range.lon.min().item()
        lon_max = ds_range.lon.max().item()

        # Subset the global dataset
        ds_subset = ds_global.sel(
            lat=slice(lat_max, lat_min),  # descending lat
            lon=slice(lon_min, lon_max)   # ascending lon
        )

        # Output directory
        outdir = os.path.join(studyarea_dir, area, "Fertilization")
        os.makedirs(outdir, exist_ok=True)
        outfile = os.path.join(outdir, f"{area}_{crop}_Fert_1981-2016.nc")

        # Save
        encoding = {var: {"_FillValue": ds_subset[var]._FillValue if "_FillValue" in ds_subset[var].attrs else None}
                    for var in ds_subset.data_vars}
        ds_subset.to_netcdf(outfile, encoding=encoding)
        print(f"✅ Saved {outfile}")
