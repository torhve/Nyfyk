function FeedListCtrl($scope, $http) {
  $http.get('/nyfyk/api/feeds/').success(function(data) {
    $scope.feeds = data;
  });
 
  $scope.orderProp = 'title';
}
function FeedCtrl($scope, $http) {
  $http.get('/nyfyk/api/items/').success(function(data) {
      console.log(data);
    $scope.feed = data;
  });
 
  $scope.orderProp = 'pubDate';
}
 
//PhoneListCtrl.$inject = ['$scope', '$http'];

