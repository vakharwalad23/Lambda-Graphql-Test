import { ApolloServer, gql } from 'apollo-server-lambda';


const typeDefs = gql`
  type Query {
    hello: String
  }
`;

const resolvers = {
  Query: {
    hello: () => 'world',
  },
};

const server = new ApolloServer({
  typeDefs,
  resolvers,
});


exports.handler = server.createHandler();