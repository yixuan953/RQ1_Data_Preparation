import os
import numpy as np
import xarray as xr

Crops = ["Rice", "Maize", "Soybean", "Wheat"]

for crop in Crops:
    indir = f"/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Fertilizer_1981-2016/{crop}"
    outfile = f"/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Fertilizer_1981-2016/{crop}_fert_1981-2016.nc"

    # Target coordinates
    years = np.arange(1981, 2017)  # 36 years
    lons = np.linspace(-179.75, 179.75, 720)
    lats = np.linspace(89.75, -89.75, 360)

    merged = xr.Dataset(coords={"year": years, "lat": lats, "lon": lons})

    for f in os.listdir(indir):
        if f.endswith(".nc"):
            path = os.path.join(indir, f)
            print(f"Processing {f}...")
            ds = xr.open_dataset(path)

            # If EF_NOx has time dimension, rename to year
            if "time" in ds.dims:
                ds = ds.rename({"time": "year"})
            
            # Force year coordinate to numeric and remove old time attributes
            if "year" in ds.coords:
                ds = ds.assign_coords(year=years)
                ds["year"].attrs = {}  # remove calendar, units, etc.
            
            # Regrid lat/lon
            ds = ds.interp(lat=lats, lon=lons, method="nearest")

            # Merge variables into master dataset
            for v in ds.data_vars:
                merged[v] = ds[v]

    # Save file
    encoding = {var: {"_FillValue": np.nan} for var in merged.data_vars}
    merged.to_netcdf(outfile, encoding=encoding)

    print(f"✅ Saved merged file to {outfile}")

