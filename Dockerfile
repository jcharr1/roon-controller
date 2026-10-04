FROM node:20-alpine

# Create app directory
WORKDIR /app

# git is required for npm to install GitHub-sourced packages
RUN apk add --no-cache git

# Install dependencies first (better layer caching)
COPY package.json ./
RUN npm install --omit=dev

# Copy source
COPY extension.js ./

# Expose REST API port
EXPOSE 3001

# Roon SOOD discovery uses UDP 9003 (handled via host networking)
# No need to expose — just use --network host or macvlan

ENV NODE_ENV=production

# node-roon-api saves its pairing token to ./config.json in the working directory.
# Run from /app/data so the token lands in a volume and survives image updates.
RUN mkdir -p /app/data
VOLUME /app/data
WORKDIR /app/data

CMD ["node", "/app/extension.js"]
