function FeedListCtrl($scope, $http) {
  $http.get('/nyfyk/api/feeds/').success(function(data) {
    $scope.feeds = data;
  });
 
  $scope.orderProp = 'title';
  $scope.selected = null;



  $scope.select = function(item) {
      $scope.selected = item;
  }

  $scope.itemClass = function(item) {
      return item === $scope.selected ? 'active' : undefined;
  };


}
function FeedCtrl($scope, $http) {
  $http.get('/nyfyk/api/items/').success(function(data) {
      console.log(data);
    $scope.feed = data;
  });
 
  $scope.orderProp = 'pubDate';
}
 
//PhoneListCtrl.$inject = ['$scope', '$http'];
//

