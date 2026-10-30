# APIM 4.7.0 public image plus the PostgreSQL JDBC driver, which the stock image does not ship.
# Built in ACR with: az acr build -r podacralior -t wso2am:4.7.0-pg1 platform/control-plane/image
FROM docker.io/wso2/wso2am:4.7.0
ARG PG_JDBC=42.7.7
ADD --chown=wso2carbon:wso2 https://repo1.maven.org/maven2/org/postgresql/postgresql/${PG_JDBC}/postgresql-${PG_JDBC}.jar \
    ${WSO2_SERVER_HOME}/repository/components/lib/postgresql-${PG_JDBC}.jar
