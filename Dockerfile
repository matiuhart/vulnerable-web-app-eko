FROM node:18-slim

ENV NODE_ENV=production
ENV PORT=8080

# Set working directory
WORKDIR /usr/src/app

#
RUN apt-get update && \
    apt-get -y upgrade

COPY package*.json npm-shrinkwrap.json* ./

RUN npm install --omit=dev && npm cache clean --force

COPY --chown=node:node . .

USER node

EXPOSE 8080

CMD ["node", "server.js"]