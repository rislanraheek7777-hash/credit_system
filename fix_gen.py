with open("lib/core/data/local/app_database.g.dart", "r") as f:
    content = f.read()
# Replace GeneratedColumn<String> customerId with GeneratedColumn<int> customerId
content = content.replace("GeneratedColumn<String> customerId", "GeneratedColumn<int> customerId")
# Replace the type DriftSqlType string to int for the customerId line
# Only replace the first occurrence that's in the loans table context
# We need to be careful: there may be other GeneratedColumn<String> customerId in other tables
# But based on analysis, only the $LoansTable has this issue
content = content.replace('type: DriftSqlType.string,', 'type: DriftSqlType.int,', 1)
with open("lib/core/data/local/app_database.g.dart", "w") as f:
    f.write(content)
print("Done")