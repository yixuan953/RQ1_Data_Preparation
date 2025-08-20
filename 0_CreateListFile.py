import pandas as pd

# Path to your Excel file
excel_file = "/lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/S1_Listfiles.xlsx"

# Read all sheets into a dictionary
all_sheets = pd.read_excel(excel_file, sheet_name=None)  # None loads all sheets

# Loop through each sheet
for sheet_name, df in all_sheets.items():
    # Create a filename based on sheet name
    txt_file = f"{sheet_name}.txt"
    
    # Export to txt (tab-separated)
    df.to_csv(txt_file, sep="\t", index=False)
    
    print(f"Exported sheet '{sheet_name}' to '{txt_file}'")