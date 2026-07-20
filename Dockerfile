FROM node:18-slim

# Set secure environment variables
ENV NODE_ENV=production
ENV PORT=8080

# Set working directory
WORKDIR /usr/src/app

# Copy dependency manifests first to leverage Docker build cache
COPY package*.json npm-shrinkwrap.json* ./

# Install only production dependencies and clean cache to minimize image size
RUN npm install --omit=dev && npm cache clean --force

# Copy the rest of the application files and set ownership to the non-root 'node' user
COPY --chown=node:node . .

# Use the non-root 'node' user for security
USER node

# Expose the application port
EXPOSE 8080

# Execute the application directly using node (properly propagates OS signals)
CMD ["node", "server.js"]