SELECT '__meta__' AS _q, TO_JSON_STRING(STRUCT(
  FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', CURRENT_TIMESTAMP()) AS savedAt,
  FORMAT_TIMESTAMP('%d/%m/%Y %H:%M', CURRENT_TIMESTAMP(), 'America/Argentina/Buenos_Aires') AS savedAtDisplay
)) AS r